import argparse
from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
from typing import Optional


PRICING_SOURCE = "https://docs.x.com/x-api/getting-started/pricing"
PRICING_CHECKED = "2026-11-04 10:41 JST"
OWNED_READ = Decimal("0.001")
POST_READ = Decimal("0.005")
USER_READ = Decimal("0.010")
GRAPH_READ = Decimal("0.010")
DM_READ = Decimal("0.010")


@dataclass(frozen=True)
class Usage:
    following: int
    followers: int
    days: int
    graph_refreshes: int
    own_events_per_day: int
    posts_per_day: int
    profiles_per_month: int
    dm_events_per_day: int
    follower_refreshes: Optional[int] = None


SCENARIOS = {
    "cleanup": (0, 0, 0),
    "hybrid": (40, 0, 50),
    "lean": (40, 30, 20),
    "balanced": (40, 100, 50),
    "active": (100, 300, 100),
}


def estimate(usage: Usage, owned: bool) -> dict[str, Decimal]:
    graph_rate = OWNED_READ if owned else GRAPH_READ
    own_rate = OWNED_READ if owned else POST_READ
    follower_refreshes = (
        usage.graph_refreshes
        if usage.follower_refreshes is None else usage.follower_refreshes
    )
    return {
        "Follower and following snapshots": (
            usage.following * usage.graph_refreshes
            + usage.followers * follower_refreshes
        ) * graph_rate,
        "Own posts and incoming mentions": usage.own_events_per_day
        * usage.days * own_rate,
        "External candidate posts": usage.posts_per_day * usage.days * POST_READ,
        "Standalone user reads": usage.profiles_per_month * USER_READ,
        "DM event reads": usage.dm_events_per_day * usage.days * DM_READ,
    }


def money(value: Decimal) -> str:
    rounded = value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return f"${rounded:,.2f}"


def nonnegative(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("Use a nonnegative resource count.")
    return parsed


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Estimate monthly X API reads in USD using published rates."
    )
    parser.add_argument("--following", type=nonnegative, default=500)
    parser.add_argument("--followers", type=nonnegative, default=200)
    parser.add_argument("--days", type=nonnegative, default=30)
    parser.add_argument("--graph-refreshes", type=nonnegative, default=4)
    parser.add_argument(
        "--follower-refreshes", type=nonnegative,
        help="Override follower refresh count; following keeps --graph-refreshes.",
    )
    parser.add_argument("--scenario", choices=SCENARIOS, default="balanced")
    parser.add_argument("--own-events-per-day", type=nonnegative)
    parser.add_argument("--posts-per-day", type=nonnegative)
    parser.add_argument("--profiles-per-month", type=nonnegative)
    parser.add_argument("--dm-events-per-day", type=nonnegative, default=0)
    parser.add_argument("--compare", action="store_true")
    args = parser.parse_args()

    def usage_for(scenario: str) -> Usage:
        own, posts, profiles = SCENARIOS[scenario]
        return Usage(
            args.following, args.followers, args.days, args.graph_refreshes,
            own if args.own_events_per_day is None else args.own_events_per_day,
            posts if args.posts_per_day is None else args.posts_per_day,
            profiles if args.profiles_per_month is None else args.profiles_per_month,
            args.dm_events_per_day, args.follower_refreshes,
        )

    print(f"Rates checked: {PRICING_CHECKED}. Source: {PRICING_SOURCE}")
    follower_refreshes = (
        args.graph_refreshes
        if args.follower_refreshes is None else args.follower_refreshes
    )
    print(f"Following: {args.following}; followers: {args.followers}; "
          f"days: {args.days}; following snapshots: {args.graph_refreshes}; "
          f"follower snapshots: {follower_refreshes}.")
    print("Estimates exclude taxes, hosting, Bot subscription, and unlisted resources.")
    print("Owned rates require an eligible owner-operated developer app.")
    if args.compare:
        print("\n| Scenario | Own events/day | External posts/day | User reads/month | Owned | Standard |")
        print("| --- | ---: | ---: | ---: | ---: | ---: |")
        for name in SCENARIOS:
            usage = usage_for(name)
            owned = sum(estimate(usage, True).values(), Decimal(0))
            standard = sum(estimate(usage, False).values(), Decimal(0))
            print(f"| {name} | {usage.own_events_per_day} | {usage.posts_per_day} "
                  f"| {usage.profiles_per_month} | {money(owned)} | {money(standard)} |")
    else:
        usage = usage_for(args.scenario)
        owned = estimate(usage, True)
        standard = estimate(usage, False)
        print("\n| Component | Owned | Standard |")
        print("| --- | ---: | ---: |")
        for label in owned:
            print(f"| {label} | {money(owned[label])} | {money(standard[label])} |")
        print(f"| Total | {money(sum(owned.values(), Decimal(0)))} "
              f"| {money(sum(standard.values(), Decimal(0)))} |")


if __name__ == "__main__":
    main()
