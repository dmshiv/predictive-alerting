"""
============================================================
WHAT  : Pub/Sub publish + subscribe helpers with batching.
WHY   : The traffic generator publishes thousands of msgs;
        the telemetry collector pulls and processes them.
HOW   : Wraps PublisherClient + SubscriberClient.
============================================================
"""
from __future__ import annotations

import json
import logging
from typing import Callable

from google.cloud import pubsub_v1

log = logging.getLogger(__name__)


class Publisher:
    def __init__(self, project_id: str):
        self.client = pubsub_v1.PublisherClient()
        self.project_id = project_id

    def topic_path(self, topic: str) -> str:
        return self.client.topic_path(self.project_id, topic)

    def publish_json(self, topic: str, payload: dict) -> str:
        """Publish a JSON-serialized message; return the message ID."""
        data = json.dumps(payload, default=str).encode("utf-8")
        future = self.client.publish(self.topic_path(topic), data)
        return future.result(timeout=10)


class Subscriber:
    def __init__(self, project_id: str):
        self.client = pubsub_v1.SubscriberClient()
        self.project_id = project_id

    def sub_path(self, subscription: str) -> str:
        return self.client.subscription_path(self.project_id, subscription)

    def subscribe(
        self,
        subscription: str,
        callback: Callable[[dict, pubsub_v1.subscriber.message.Message], None],
    ):
        """Streaming pull. callback(payload_dict, raw_msg) -> caller acks."""
        def _wrapper(msg: pubsub_v1.subscriber.message.Message) -> None:
            try:
                payload = json.loads(msg.data.decode("utf-8"))
                callback(payload, msg)
            except Exception:
                log.exception("subscriber callback error; nacking")
                msg.nack()

        future = self.client.subscribe(self.sub_path(subscription), _wrapper)
        log.info("listening on subscription", extra={"subscription": subscription})
        return future
