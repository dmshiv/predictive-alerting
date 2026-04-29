"""
============================================================
WHAT  : KFP component — register a trained model in Vertex AI
        Model Registry and (optionally) deploy to an endpoint.
============================================================
"""
from __future__ import annotations

from kfp import dsl


@dsl.component(
    base_image="python:3.11-slim",
    packages_to_install=["google-cloud-aiplatform==1.71.0"],
)
def register_model_op(
    project_id: str,
    region: str,
    model_uri: str,
    display_name: str,
    serving_container: str,
    endpoint_name: str,
) -> str:
    """Upload model artifact to Model Registry; deploy to endpoint."""
    import logging
    from google.cloud import aiplatform

    logging.basicConfig(level="INFO")
    log = logging.getLogger("register_model_op")

    aiplatform.init(project=project_id, location=region)

    # Upload to Model Registry
    model = aiplatform.Model.upload(
        display_name=display_name,
        artifact_uri=model_uri,
        serving_container_image_uri=serving_container,
    )
    log.info("registered model: %s", model.resource_name)

    # Find or create endpoint by display name
    endpoints = aiplatform.Endpoint.list(filter=f'display_name="{endpoint_name}"')
    if endpoints:
        endpoint = endpoints[0]
    else:
        endpoint = aiplatform.Endpoint.create(display_name=endpoint_name)

    # Deploy with traffic 100% to new model
    model.deploy(
        endpoint=endpoint,
        machine_type="n1-standard-2",
        min_replica_count=1,
        max_replica_count=2,
        traffic_percentage=100,
    )
    log.info("deployed to endpoint: %s", endpoint.resource_name)
    return model.resource_name
