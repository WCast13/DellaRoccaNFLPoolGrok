# UX checklist

Edit this file as the list changes. Checked items are in the app. Unchecked items are still open.

- [x] 1. Make the Pool tab live. Load standings from Firestore. Show a pick only after that game has kicked off.
- [x] 2. Show every week that has kicked off on a pool row, and mark the week that knocked the entry out. A bought-back week is marked too, so a loss does not look like a win.
- [ ] 3. Let pool search find a team as well as an entry name.
- [x] 4. Open My Entries when someone is already signed in. Keep Pool as a tab.
- [x] 5. Show the Commissioner tab only on an admin account.
- [x] 6. Keep "Claim another entry" after the first PIN.
- [x] 7. Show every entry on My Entries with this week's team, or "No pick."
- [x] 8. Make the saved pick obvious. The button stays on screen and reads "Jets saved" or "Save Jets." The confirmation sits at the top.
- [x] 9. Say why a team cannot be picked: "Used in week 2" or "Locked."
- [ ] 10. Show the score once a game starts, and label the spread as a spread.
- [ ] 11. Say that this week's result is still open before offering next week's games.
- [x] 12. Tell a knocked-out player which week they lost and give them the buyback decision themselves: buy back in or stay eliminated, changeable until the deadline, confirmed by making the next week's pick. The fee is still settled outside the app and shows as owed.
- [x] 13. Turn the commissioner home into three queues with counts: no pick yet, waiting on a buyback, and no login. Name search still finds any entry. (Replaced by the week grid in item 17; the counts live in the week summary now.)
- [ ] 14. Ask before changing a pick whose game has already kicked off. (The close-week preview half of this item is gone — weeks grade automatically now.)
- [x] 15. Put the team name on the pick button. Show the logo stored for that team.
- [x] 16. Show who has commissioner access, and let a commissioner remove one. Removal revokes the claim on the server; it takes effect on that person's next sign-in refresh, within an hour.
- [x] 17. Commissioner tab as a week board: a header to step or jump weeks, the week's games as a slate, and every entry's picks in one aligned grid. Grading runs on its own each hour; "Sync scores and grade now" runs it on demand.
- [x] 18. Summarize the selected week above the grid: entries active, won, lost, waiting, and with no pick, plus how many entries picked each team, ringed green or red once that game is final.
- [x] 19. Filter the grid with a segmented control: Eliminated is every entry whose status is eliminated, Active is everyone else, including a knocked-out entry with its buyback still open. Search narrows within the chosen segment.
- [x] 20. Tap an entry's name on the grid to open a popup for that week: the teams it can still pick on top, the teams it has used dimmed beneath with the week they went. Saving closes the popup and the grid cell updates. Buyback overrides and "mark fee paid" live in the same popup.
