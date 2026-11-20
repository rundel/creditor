use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use extendr_api::prelude::*;
use loro::awareness::{EphemeralEventTrigger, EphemeralStoreEvent};
use loro::event::DiffEvent;
use loro::{EventTriggerKind, Subscription};

use crate::history::diffs_to_r;

/// Events are converted to R objects when Loro fires them and held here
/// until R collects them, so that R callbacks never run inside Loro.
///
/// Loro requires its callbacks to be `Send + Sync`, which `Robj` is not.
/// The queue is only ever touched from R's main thread: Loro invokes
/// subscribers synchronously on the thread that commits or imports, and
/// this package never calls Loro from any other thread.
/// Number of events waiting in all queues. R checks this one value before
/// scanning its registry, so that a call which produced no events costs the
/// same however many subscriptions exist.
static PENDING: AtomicUsize = AtomicUsize::new(0);

pub fn pending() -> usize {
    PENDING.load(Ordering::Relaxed)
}

pub struct EventQueue(Mutex<Vec<Robj>>);

unsafe impl Send for EventQueue {}
unsafe impl Sync for EventQueue {}

impl EventQueue {
    pub fn new() -> Arc<Self> {
        Arc::new(EventQueue(Mutex::new(Vec::new())))
    }

    pub fn push(&self, event: Robj) {
        if let Ok(mut queue) = self.0.lock() {
            queue.push(event);
            PENDING.fetch_add(1, Ordering::Relaxed);
        }
    }

    pub fn take(&self) -> Vec<Robj> {
        match self.0.lock() {
            Ok(mut queue) => {
                let events = std::mem::take(&mut *queue);
                PENDING.fetch_sub(events.len(), Ordering::Relaxed);
                events
            }
            Err(_) => Vec::new(),
        }
    }
}

pub struct QueuedSubscription {
    subscription: Mutex<Option<Subscription>>,
    queue: Arc<EventQueue>,
}

impl QueuedSubscription {
    pub fn new(subscription: Subscription, queue: Arc<EventQueue>) -> Self {
        QueuedSubscription {
            subscription: Mutex::new(Some(subscription)),
            queue,
        }
    }

    pub fn take(&self) -> List {
        List::from_values(self.queue.take())
    }

    pub fn cancel(&self) {
        if let Ok(mut subscription) = self.subscription.lock() {
            if let Some(subscription) = subscription.take() {
                subscription.unsubscribe();
            }
        }
        self.queue.take();
    }
}

pub fn event_to_r(event: &DiffEvent) -> Robj {
    let by = match event.triggered_by {
        EventTriggerKind::Local => "local",
        EventTriggerKind::Import => "import",
        EventTriggerKind::Checkout => "checkout",
    };
    let diff = diffs_to_r(event.events.iter().map(|e| (e.target, &e.diff)));
    list!(by = by, origin = event.origin, diff = diff).into()
}

pub fn ephemeral_event_to_r(event: &EphemeralStoreEvent) -> Robj {
    let by = match event.by {
        EphemeralEventTrigger::Local => "local",
        EphemeralEventTrigger::Import => "import",
        EphemeralEventTrigger::Timeout => "timeout",
    };
    list!(
        by = by,
        added = event.added.as_ref().clone(),
        updated = event.updated.as_ref().clone(),
        removed = event.removed.as_ref().clone()
    )
    .into()
}

impl Drop for EventQueue {
    fn drop(&mut self) {
        self.take();
    }
}
