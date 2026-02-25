"""
MarketPulse Risk Profile Scorer - AWS Lambda Function

Assesses whether a stock is suitable for a client's risk profile.
This function demonstrates the Lambda Gateway target pattern in AgentCore.

In a production FSI system, this would plug into proprietary risk models.
For the workshop, a rule-based matrix illustrates the concept clearly.

Input:
    ticker:       Stock ticker symbol (e.g., AAPL, TSLA)
    risk_profile: Client profile - "conservative", "moderate", or "aggressive"

Output:
    suitability:         "clear_match", "proceed_with_caution", or "not_suitable"
    reasoning:           Plain-language explanation for the advisor
    ticker:              Echo of input ticker (upper-cased)
    risk_profile:        Echo of input risk profile
    volatility_assessed: Volatility category used in the assessment
"""

import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ---------------------------------------------------------------------------
# Volatility classification
# Simplified for workshop clarity - production systems use rolling std dev
# ---------------------------------------------------------------------------
VOLATILITY_MAP: dict[str, str] = {
    "AAPL": "low",
    "MSFT": "low",
    "BRK.B": "low",
    "JNJ": "low",
    "GOOGL": "medium",
    "AMZN": "medium",
    "META": "medium",
    "V": "low",
    "TSLA": "high",
    "NVDA": "high",
    "AMD": "high",
    "COIN": "high",
}

# ---------------------------------------------------------------------------
# Suitability matrix: (risk_profile, volatility) -> (suitability, reasoning)
# ---------------------------------------------------------------------------
SUITABILITY_MATRIX: dict[tuple[str, str], tuple[str, str]] = {
    ("conservative", "low"): (
        "clear_match",
        "Established company with stable earnings and low price volatility - "
        "well aligned with conservative capital preservation goals.",
    ),
    ("conservative", "medium"): (
        "proceed_with_caution",
        "Moderate volatility may cause drawdowns that exceed conservative risk "
        "tolerance. Consider limiting position size.",
    ),
    ("conservative", "high"): (
        "not_suitable",
        "High price volatility is inappropriate for a conservative portfolio. "
        "Capital preservation should be the priority for this client.",
    ),
    ("moderate", "low"): (
        "clear_match",
        "Stable investment provides a solid foundation for a balanced portfolio.",
    ),
    ("moderate", "medium"): (
        "clear_match",
        "Volatility aligns well with moderate risk tolerance and growth objectives.",
    ),
    ("moderate", "high"): (
        "proceed_with_caution",
        "Higher volatility than typical moderate allocation. Keep position size "
        "proportionate to overall portfolio risk budget.",
    ),
    ("aggressive", "low"): (
        "clear_match",
        "Quality, stable company suitable as a defensive anchor in a growth portfolio.",
    ),
    ("aggressive", "medium"): (
        "clear_match",
        "Good growth-oriented investment with manageable volatility for this risk profile.",
    ),
    ("aggressive", "high"): (
        "clear_match",
        "High growth potential is appropriate for an aggressive risk tolerance. "
        "Ensure portfolio-level diversification is maintained.",
    ),
}


def handler(event: dict, context) -> dict:
    """
    Lambda handler for risk profile scoring.

    AgentCore Gateway passes the tool arguments directly as the event payload.
    """
    logger.info("Risk scorer invoked with event: %s", json.dumps(event))

    ticker = event.get("ticker", "").strip().upper()
    risk_profile = event.get("risk_profile", "").strip().lower()

    # --- Validate inputs ---
    if not ticker:
        return _error_response("ticker is required")

    valid_profiles = {"conservative", "moderate", "aggressive"}
    if risk_profile not in valid_profiles:
        return _error_response(
            f"risk_profile must be one of: {', '.join(sorted(valid_profiles))}. "
            f"Received: '{risk_profile}'"
        )

    # --- Assess volatility ---
    volatility = VOLATILITY_MAP.get(ticker, "medium")
    logger.info("Ticker=%s volatility=%s risk_profile=%s", ticker, volatility, risk_profile)

    # --- Look up suitability ---
    suitability, reasoning = SUITABILITY_MATRIX.get(
        (risk_profile, volatility),
        ("proceed_with_caution", "Suitability could not be determined with available data."),
    )

    result = {
        "ticker": ticker,
        "risk_profile": risk_profile,
        "suitability": suitability,
        "reasoning": reasoning,
        "volatility_assessed": volatility,
    }

    logger.info("Assessment result: %s", json.dumps(result))

    # AgentCore Gateway expects the tool result in the response body
    return {
        "statusCode": 200,
        "body": json.dumps(result),
    }


def _error_response(message: str) -> dict:
    logger.error("Validation error: %s", message)
    return {
        "statusCode": 400,
        "body": json.dumps({"error": message}),
    }
