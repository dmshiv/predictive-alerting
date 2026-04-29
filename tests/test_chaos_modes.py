"""Chaos generators must produce valid samples & differ from baseline."""
import statistics

from src.ingestion.chaos_modes import MODE_GENERATORS, get_generator, sleep_between


def test_all_modes_callable():
    for mode in MODE_GENERATORS:
        get_generator(mode)()  # no exception


def test_drift_shifts_image_norm():
    base = [get_generator("baseline")().image_embedding_norm for _ in range(200)]
    drift = [get_generator("drift")().image_embedding_norm for _ in range(200)]
    assert statistics.mean(drift) > statistics.mean(base) + 0.15


def test_latency_increases_request_latency():
    base = [get_generator("baseline")().request_latency_ms for _ in range(200)]
    lat = [get_generator("latency")().request_latency_ms for _ in range(200)]
    assert statistics.mean(lat) > statistics.mean(base) + 200


def test_off_returns_none():
    assert get_generator("off")() is None


def test_sleep_between_burst_is_fast():
    assert sleep_between("burst") < sleep_between("baseline")
