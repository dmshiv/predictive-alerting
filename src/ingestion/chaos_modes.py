"""
============================================================
WHAT  : Defines what each demo "chaos mode" does to the
        synthetic traffic the load-gen produces.
WHY   : So `chaos_inject.py --mode=drift` produces a
        well-defined, reproducible failure pattern that the
        forecaster can actually predict.
HOW   : Each mode is a function (random_input) -> mutated_input.
LAYMAN: A library of "ways to mess with the AI" we can press
        a button to enable for the live demo.
============================================================
"""
from __future__ import annotations

import random
import time
from dataclasses import dataclass
from typing import Callable


@dataclass
class TrafficSample:
    """One synthetic shopper request."""
    user_id: str
    review_text: str
    image_embedding_norm: float    # synthetic feature: norm of image embedding (drift target)
    review_token_count: int        # synthetic feature: text length proxy
    request_latency_ms: float      # what the model "took" to respond
    error: bool                    # whether the model errored on this request


# --- Helpers -----------------------------------------------------------------

_REVIEW_SAMPLES = [
    "These shoes are so comfortable and stylish",
    "Worst purchase ever, falling apart in a week",
    "Decent value for the price; runs small",
    "Love the color; great for casual wear",
    "Sole came off after 2 weeks; do not buy",
    "Perfect fit and great support",
]


def _baseline_sample(user_id: str | None = None) -> TrafficSample:
    """Healthy baseline traffic — no drift, no latency, no errors."""
    return TrafficSample(
        user_id=user_id or f"u{random.randint(1, 10000)}",
        review_text=random.choice(_REVIEW_SAMPLES),
        image_embedding_norm=random.gauss(1.0, 0.1),       # ~N(1.0, 0.1)
        review_token_count=random.randint(8, 40),
        request_latency_ms=random.gauss(120, 25),          # ~120ms p50
        error=False,
    )


# --- Mode generators ---------------------------------------------------------

def _baseline() -> TrafficSample:
    return _baseline_sample()


def _drift() -> TrafficSample:
    """Shift `image_embedding_norm` distribution +2σ (mimics user-uploaded
    selfies replacing studio photos). p99 latency creeps up because the
    recommender's image branch hits OOD inputs."""
    s = _baseline_sample()
    s.image_embedding_norm = random.gauss(1.3, 0.2)        # +0.3 mean, wider tail
    s.request_latency_ms = random.gauss(160, 60)           # creeps up + variance
    return s


def _latency() -> TrafficSample:
    """Hardware-flavored failure: latency spikes; some errors."""
    s = _baseline_sample()
    s.request_latency_ms = random.gauss(700, 250)
    s.error = random.random() < 0.05
    return s


def _burst() -> TrafficSample:
    """Healthy data, just a lot more of it (HPA test)."""
    return _baseline_sample()


def _off() -> TrafficSample | None:
    """Idle. Caller should sleep instead of generating."""
    return None


# --- Public API --------------------------------------------------------------

MODE_GENERATORS: dict[str, Callable[[], TrafficSample | None]] = {
    "baseline": _baseline,
    "drift": _drift,
    "latency": _latency,
    "burst": _burst,
    "off": _off,
}

MODE_RATE_PER_SEC: dict[str, int] = {
    "baseline": 30,
    "drift": 30,
    "latency": 30,
    "burst": 200,
    "off": 0,
}


def get_generator(mode: str) -> Callable[[], TrafficSample | None]:
    if mode not in MODE_GENERATORS:
        raise ValueError(f"unknown chaos mode: {mode}")
    return MODE_GENERATORS[mode]


def sleep_between(mode: str) -> float:
    """Seconds to sleep between generated samples for a given mode."""
    rate = MODE_RATE_PER_SEC.get(mode, 0)
    if rate <= 0:
        return 5.0
    return 1.0 / rate
