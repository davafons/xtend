# Where Xtend's data comes from

Xtend never assumes it saw everything. Each source covers something different, and every page says how complete its data is: a missing value shows as missing, not zero, and missing history is never treated as proof that something didn't happen.

| Source | What it brings | Cost |
| --- | --- | --- |
| [X archive](setup.md#1-request-your-x-archive) | Every post and reply you wrote up to the archive's date, the people you replied to, and one-to-one DM metadata (who and when, never text). | Free |
| [Browser extension](../extension/README.md) | Whatever x.com loads while you browse: timelines, profiles, threads, notifications, likes and bookmarks you make, follow states, complete follow lists when you scroll them to the end, and your X analytics. | Free |
| X API | Your follower and following lists, your recent posts and mentions, likes, bookmarks, and DMs, one page per button press. | Pay per use, against your allowance |

## People and replies

A reply you send creates or updates a person for whoever you replied to. Reply history counts both ways and classifies each reply: a first reply to a post you hadn't answered counts toward an Outreach session; follow-ups in the same exchange, repeats, and replies to yourself don't. The same post from two sources is saved once.

Your own choices (pins, keep-following, tags, notes, reminders) are never overwritten by a sync, an import, or an AI.

## Follow state and follower changes

Whether you follow someone, and whether they follow you, comes from the newest evidence: a complete follow list, an API check, or the follow state x.com shows on each account. A list counts as complete only when every page continued from the one before and the total matches your profile's count.

Follower changes compare complete follower lists. A new follower appeared between the previous complete list and the new one; a lost follower disappeared between their last sighting and the later list. Partial lists can't establish a loss, and follows and unfollows between two checks stay invisible. The first complete list is a baseline: its followers' original follow dates are unknown.

Follow review needs a complete follower list less than a day old before it suggests anyone, because older or partial data can't prove someone isn't following you back. It never suggests people you marked to keep or anyone you've exchanged replies with.

## X analytics

Opening Analytics on x.com with the extension on saves X's own figures: daily counts (impressions, profile visits, follows, and more), each post's and reply's private totals, the hourly activity heatmap, and who saw you. X counts a day about a day later, and only the range and metric you pick on x.com are saved. Outreach and Growth say when they're more than a week old.

## X API costs

X bills per returned resource. At the rate for apps you own, a follower or following record costs about $0.001 and one of your posts about $0.001; an outside post costs about $0.005 and a standalone profile read about $0.01. Check [X's pricing](https://docs.x.com/x-api/getting-started/pricing) for current rates.

`scripts/estimate-x-costs.py --following 500 --followers 200` estimates a month for your account. The **Spending** page holds Xtend's allowance and a ledger of what each read cost by its estimate; the developer console has the real bill.
