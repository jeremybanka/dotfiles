# Synthetic writer used only by chats-live.nu. Keep committing WAL data and
# appending history while the foreground process captures its earlier cutoff.
def main [directory: string] {
  let settings = (open ($directory | path join writer.json))
  'ready' | save --raw ($directory | path join ready)
  mut sequence = 0
  while not (($directory | path join stop) | path exists) {
    let line = (({type: event_msg payload: {type: token_count value: $sequence}} | to json --raw) + "\n")
    $line | save --raw --append $settings.rollout
    let statement = $"PRAGMA journal_mode=WAL; UPDATE threads SET tokens_used=($sequence) WHERE id='($settings.thread)';"
    let result = (do { ^sqlite3 -cmd '.timeout 5000' $settings.database $statement } | complete)
    if $result.exit_code != 0 { error make {msg: $result.stderr} }
    $sequence = $sequence + 1
    $sequence | into string | save --raw -f ($directory | path join count.incoming)
    mv -f ($directory | path join count.incoming) ($directory | path join count)
    sleep 20ms
  }
}
