"""
MarketPulse MCP Server - Market Calendar for Financial Advisors

Wraps the Nager.Date public holidays API to expose market calendar
information as an MCP tool. Deployed to AgentCore Runtime alongside the
MarketPulse agent.

Module 4: MCP Gateway Target
"""

import logging
import os
from datetime import datetime, timedelta

import httpx
from mcp.server.fastmcp import FastMCP

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# AgentCore Runtime requires stateless_http=True (no persistent sessions)
# The platform provides session isolation and adds Mcp-Session-Id headers
mcp = FastMCP("market-calendar", host="0.0.0.0", stateless_http=True)

NAGER_DATE_BASE_URL = "https://date.nager.at/api/v3"


@mcp.tool()
async def check_market_holidays(
    country_code: str = "AU",
    days_ahead: int = 7,
) -> dict:
    """
    Check for public holidays that affect market trading in the next N days.

    Retrieves scheduled public holidays from Nager.Date for the specified
    country. Advisors should factor these in when planning trade executions
    and client meeting timing.

    Args:
        country_code: ISO 3166-1 alpha-2 country code (e.g. AU, US, GB).
                      Defaults to AU for Australian markets.
        days_ahead:   Number of calendar days to look ahead. Defaults to 7.

    Returns:
        dict: Upcoming holidays with dates, names, and trading impact summary.
    """
    today = datetime.now()
    end_date = today + timedelta(days=days_ahead)

    # Fetch holidays for current year; if the window spans new year, fetch next year too
    years = {today.year}
    if end_date.year != today.year:
        years.add(end_date.year)

    all_holidays: list[dict] = []

    async with httpx.AsyncClient(timeout=10.0) as client:
        for year in sorted(years):
            url = f"{NAGER_DATE_BASE_URL}/PublicHolidays/{year}/{country_code}"
            logger.info(f"Fetching holidays from {url}")

            try:
                response = await client.get(url)
                response.raise_for_status()
                all_holidays.extend(response.json())
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 404:
                    logger.warning(f"No holiday data for country_code={country_code}")
                    return {
                        "error": f"Country code '{country_code}' not found in Nager.Date",
                        "valid_examples": ["AU", "US", "GB", "NZ", "JP"],
                    }
                logger.error(f"Nager.Date API error: {e}")
                return {"error": f"Holiday API returned {e.response.status_code}"}
            except httpx.RequestError as e:
                logger.error(f"Nager.Date request failed: {e}")
                return {"error": "Failed to reach holiday data service"}

    # Filter to the requested date window
    upcoming: list[dict] = []
    for holiday in all_holidays:
        holiday_date = datetime.strptime(holiday["date"], "%Y-%m-%d")
        if today.date() <= holiday_date.date() <= end_date.date():
            upcoming.append(
                {
                    "date": holiday["date"],
                    "name": holiday["localName"],
                    "is_trading_day": False,
                }
            )

    return {
        "country_code": country_code,
        "period_start": today.strftime("%Y-%m-%d"),
        "period_end": end_date.strftime("%Y-%m-%d"),
        "holidays": upcoming,
        "trading_days_affected": len(upcoming),
        "advice": (
            f"{len(upcoming)} market closure(s) in the next {days_ahead} days. "
            "Plan trade executions and client meetings accordingly."
            if upcoming
            else f"No scheduled market closures in the next {days_ahead} days."
        ),
    }


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    logger.info(f"Starting MarketPulse MCP server on port {port}")
    # transport="streamable-http" is required for AgentCore Runtime
    # AgentCore expects the MCP endpoint at 0.0.0.0:8000/mcp
    mcp.run(transport="streamable-http")
