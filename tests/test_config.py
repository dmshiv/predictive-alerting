"""Sanity tests for the central config loader."""
from src.utils.config import Config, get_config


def test_get_config_basic():
    # Bust the lru_cache before each test
    get_config.cache_clear()
    cfg = get_config()
    assert cfg.project_id == "test-project"
    assert cfg.region == "us-central1"
    assert cfg.env_name == "test"


def test_derived_names():
    get_config.cache_clear()
    cfg = get_config()
    assert cfg.name_prefix == "sentinel-test"
    assert cfg.bucket_models == "test-project-sentinel-test-models"
    assert cfg.topic_telemetry == "sentinel-test-telemetry"
    # BQ dataset names: hyphens replaced with underscores
    assert "_test_features" in cfg.bq_dataset_features
    assert cfg.endpoint_victim.endswith("/endpoints/victim-recommender")
