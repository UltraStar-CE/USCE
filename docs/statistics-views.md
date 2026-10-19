# Statistics views

Choose **Options → Game → Statistics**:

- **Reduced** shows library totals and saved-score counts for the selected time
  range. Song and artist popularity tables show play counts.
- **Full** shows the detailed overview: video coverage, average scores, library
  coverage, scores per player and song, recent activity and its comparison with
  all-time activity, and five facts drawn from saved performances. Headings and
  the people, songs and values in facts are highlighted in bold. Song and artist
  popularity tables also include average scores.

Reduced is the default. The setting is saved as `[Game] StatisticsView=Reduced`
or `StatisticsView=Full` in the configuration file.

Both views share queries, time ranges, pagination, table layout, text fitting,
and translations. Singer tables retain score counts and their optional minimum
sample-size filter. Full retains the earlier detailed statistics presentation
while using the shared table helpers and time-range navigation. Recent activity
is shown alongside all-time statistics; selecting a time range applies that
range to the overview and facts instead.
