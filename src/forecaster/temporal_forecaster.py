"""
============================================================
WHAT  : The time-series forecaster — AI #2's core.
WHY   : Predicts the next `horizon` minutes of every metric
        given the last `lookback` minutes. So we can fire
        an alert before the SLO breaks.
HOW   : Encoder LSTM -> latent -> Decoder Dense -> output.
        (A simpler stand-in for a Temporal Fusion Transformer;
        easier to train on small data and faster to deploy.)
LAYMAN: Watch the last hour of vital signs, predict the
        next 2 hours.
JD KEYWORD: TensorFlow / Keras, time-series
============================================================
"""
from __future__ import annotations

import logging

import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers

log = logging.getLogger(__name__)


def build_forecaster(
    n_features: int,
    lookback: int = 60,
    horizon: int = 120,
    hidden: int = 64,
) -> keras.Model:
    """Encoder-decoder LSTM that maps (lookback, F) -> (horizon, F)."""

    inp = keras.Input(shape=(lookback, n_features), name="lookback")
    x = layers.LSTM(hidden, return_sequences=False, name="encoder")(inp)
    x = layers.Dropout(0.1)(x)
    # Project to (horizon * n_features) then reshape — simple but effective
    x = layers.Dense(horizon * n_features, name="decoder_dense")(x)
    out_mean = layers.Reshape((horizon, n_features), name="forecast_mean")(x)

    # Predict an upper-bound multiplier so we get an interval (P95) cheaply
    band = layers.Dense(horizon * n_features, activation="softplus", name="decoder_band")(
        layers.LSTM(hidden, return_sequences=False)(inp)
    )
    band = layers.Reshape((horizon, n_features), name="forecast_band")(band)

    model = keras.Model(inputs=inp, outputs={"mean": out_mean, "band": band})
    return model


def mean_mse(y_true, y_pred):
    """Plain MSE loss applied to the 'mean' head only."""
    return tf.reduce_mean(tf.square(y_true - y_pred))


def band_magnitude_loss(y_true, y_pred):
    """Keep the 'band' head close to |y_true| so it captures expected variation.

    The softplus activation already enforces band >= 0. By training it to predict
    the absolute value of the (normalized) target, we get a per-step uncertainty
    width that correlates with how much the metric typically varies. At inference,
    ``predict_breach`` multiplies this by the per-feature std, giving a sensible
    band in the original units.
    """
    return tf.reduce_mean(tf.abs(tf.abs(y_true) - y_pred))


# Backwards-compat alias used by older code paths / pipelines.
forecaster_loss = mean_mse
