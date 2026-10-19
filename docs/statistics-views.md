# Statistics views

Choose **Options → Game → Statistics**:

- **Reduced** keeps the compact overview from the statistics redesign.
- **Full** emphasizes section titles, people, songs, artists and numbers in
  the overview, and includes average saved-score counts per player and per song.

Reduced is the default. The setting is saved as `[Game] StatisticsView=Reduced`
or `StatisticsView=Full` in the configuration file.

Both views use the same database queries, time ranges, detail tables, paging,
median filter, text fitting and translations. Changing presentation does not
reset statistics or change rankings. Full uses the existing inline-bold renderer
and overview layout; themes do not need a second statistics screen.
