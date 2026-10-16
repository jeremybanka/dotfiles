#!/usr/bin/env nu

use ./lib.nu *

def short-rev [rev: string, length: int = 12] {
  let trimmed = ($rev | str trim)

  if $trimmed == "" {
    ""
  } else if ($trimmed | str length) <= $length {
    $trimmed
  } else {
    $trimmed | str substring 0..($length - 1)
  }
}

def colorize [text: string, color: string, use_color: bool] {
  if not $use_color {
    $text
  } else {
    $"(ansi $color)($text)(ansi reset)"
  }
}

def format-utc [value: string] {
  if $value == "" {
    ""
  } else if ($value | str contains " UTC") {
    $value
  } else {
    $value | str replace "T" " " | str replace "Z" " UTC"
  }
}

def parse-first [text: string, pattern: string, message: string] {
  let matches = ($text | parse --regex $pattern)

  if ($matches | is-empty) {
    error make { msg: $message }
  } else {
    $matches | first
  }
}

def parse-count [text: string, label: string] {
  let pattern = ([$label ' \((?P<count>[0-9]+)\)'] | str join '')
  let parsed = ($text | parse --regex $pattern)

  if ($parsed | is-empty) {
    0
  } else {
    $parsed | first | get count | into int
  }
}

def extract-release-short-rev [release_name: string] {
  let parsed = ($release_name | parse --regex '(?P<rev>[a-f0-9]{12})$')

  if ($parsed | is-empty) {
    ""
  } else {
    $parsed | first | get rev
  }
}

def fetch-url [url: string] {
  let result = (do { ^curl --silent --show-error --location $url } | complete)

  if $result.exit_code != 0 {
    error make {
      msg: $"Failed to fetch ($url)."
      label: {
        text: (
          $result.stderr
          | str trim
          | default $"curl exited with code ($result.exit_code)"
        )
      }
    }
  }

  $result.stdout
}

def fetch-prometheus-query [query: string] {
  let query_arg = ($query | url encode)
  let url = $"https://prometheus.nixos.org/api/v1/query?query=($query_arg)"
  let parsed = ((fetch-url $url) | from json)
  let rows = ($parsed.data.result | default [])

  if ($rows | is-empty) {
    error make { msg: $"Prometheus query returned no results: ($query)" }
  }

  $rows | first
}

def load-local-pin [] {
  let vms_root = (vms-dir)
  let flake_nix = (open --raw ($vms_root | path join "flake.nix"))
  let flake_lock = (open --raw ($vms_root | path join "flake.lock") | from json)
  let ref = (
    parse-first $flake_nix 'nixpkgs-unstable\.url = "github:NixOS/nixpkgs/(?P<ref>[^"]+)";' "Could not determine the nixpkgs-unstable ref from vms/flake.nix."
    | get ref
  )
  let revision = ($flake_lock.nodes."nixpkgs-unstable".locked.rev | default "")

  {
    ref: $ref
    revision: $revision
    short_revision: (short-rev $revision)
  }
}

def parse-published-channel [html: string] {
  let parsed = (
    parse-first $html '(?s)<h1>nixpkgs-unstable release (?P<release_name>[^<]+)</h1><p>Released on (?P<released_at>[^<]+) from <a href=[^>]+>Git commit <tt>(?P<commit>[a-f0-9]{40})</tt></a> from (?P<source_at>[^<]+) via <a href=[^>]*eval/(?P<eval_id>[0-9]+)[^>]*>Hydra evaluation [0-9]+</a>' "Could not parse the published nixpkgs-unstable release page."
  )

  {
    release_name: $parsed.release_name
    released_at: ($parsed.released_at | str trim)
    source_at: ($parsed.source_at | str trim)
    revision: $parsed.commit
    short_revision: (short-rev $parsed.commit)
    eval_id: ($parsed.eval_id | into int)
  }
}

def parse-latest-eval-row [html: string] {
  let parsed = (
    parse-first $html '(?s)<td><a class="row-link" href="https://hydra.nixos.org/eval/(?P<eval_id>[0-9]+)">[0-9]+</a></td>\s*<td class="nowrap"><time[^>]*datetime="(?P<started_at>[^"]+)"[^>]*>.*?</td>\s*<td>nixpkgs →\s*<a class="rev-copy"[^>]*title="Click to copy full revision: (?P<revision>[a-f0-9]{40})"[^>]*><tt>(?P<short_revision>[a-f0-9]{12})</tt></a>(?:\s*<span class="badge badge-warning">(?P<badge>[^<]+)</span>)?' "Could not parse the latest nixpkgs:unstable evaluation row."
  )

  {
    eval_id: ($parsed.eval_id | into int)
    started_at: (format-utc $parsed.started_at)
    revision: $parsed.revision
    short_revision: $parsed.short_revision
    badge: ($parsed.badge | default "" | str trim)
  }
}

def parse-eval-summary [html: string] {
  {
    aborted_jobs: (parse-count $html "Aborted / Timed out Jobs")
    newly_failing_jobs: (parse-count $html "Newly Failing Jobs")
    still_failing_jobs: (parse-count $html "Still Failing Jobs")
    queued_jobs: (parse-count $html "Queued Jobs")
  }
}

def parse-hydra-queue [html: string] {
  let parsed = (
    parse-first $html 'Queue \((?P<running>[0-9]+)/(?P<queued>[0-9]+)\)' "Could not parse the global Hydra queue summary."
  )

  {
    running: ($parsed.running | into int)
    queued: ($parsed.queued | into int)
  }
}

def parse-unstable-queue-row [html: string] {
  let parsed = (
    parse-first $html '(?s)jobset/nixpkgs/unstable"><tt>unstable</tt></a></tt></td>\s*<td>(?P<queued>[0-9]+)</td>\s*<td><time[^>]*datetime="(?P<oldest>[^"]+)"[^>]*>.*?</td>\s*<td><time[^>]*datetime="(?P<newest>[^"]+)"[^>]*>.*?</td>' "Could not parse the nixpkgs:unstable row from the Hydra queue summary."
  )

  {
    queued: ($parsed.queued | into int)
    oldest_queued_at: (format-utc $parsed.oldest)
    newest_queued_at: (format-utc $parsed.newest)
  }
}

def parse-gate-job [html: string] {
  let latest = (
    parse-first $html '(?s)<h3>Latest builds</h3>.*?<tbody>\s*<tr>\s*<td>\s*<img [^>]*title="(?P<status>[^"]+)"[^>]*>\s*</td>\s*<td><a class="row-link" href="https://hydra.nixos.org/build/(?P<build_id>[0-9]+)">[0-9]+</a></td>\s*<td class="nowrap"><time[^>]*datetime="(?P<finished_at>[^"]+)"[^>]*>.*?</td>\s*<td>(?P<release_name>nixpkgs-[^<]+)</td>' "Could not parse the latest nixpkgs/unstable/unstable build row."
  )

  let queued_candidates = (
    $html
    | parse --regex '(?s)<td><span class="badge badge-secondary">Queued</span></td>\s*<td><a class="row-link" href="https://hydra.nixos.org/build/(?P<build_id>[0-9]+)">[0-9]+</a></td>\s*<td class="nowrap"><time[^>]*datetime="(?P<queued_at>[^"]+)"[^>]*>.*?</td>\s*<td>(?P<release_name>nixpkgs-[^<]+)</td>'
  )
  let newest_queued_candidate = if ($queued_candidates | is-empty) {
    null
  } else {
    let newest = ($queued_candidates | sort-by queued_at | last)
    {
      build_id: ($newest.build_id | into int)
      queued_at: (format-utc $newest.queued_at)
      release_name: $newest.release_name
      short_revision: (extract-release-short-rev $newest.release_name)
    }
  }

  {
    latest_status: ($latest.status | str trim)
    latest_build_id: ($latest.build_id | into int)
    latest_finished_at: (format-utc $latest.finished_at)
    latest_release_name: $latest.release_name
    latest_short_revision: (extract-release-short-rev $latest.release_name)
    queued_builds: ($queued_candidates | length)
    newest_queued_candidate: $newest_queued_candidate
  }
}

def build-assessment [published: record, latest_eval: record, gate: record, gate_failed: bool, unstable_queue: record] {
  let gate_ahead = (
    $gate.latest_status == "Succeeded"
    and $gate.latest_short_revision != ""
    and $gate.latest_short_revision != $published.short_revision
  )
  let queues_active = ($unstable_queue.queued > 0 or $latest_eval.queued_jobs > 0 or $gate.queued_builds > 0)
  let eval_badge = ($latest_eval.badge | default "" | str trim)

  if $gate_failed {
    {
      state: "blocked"
      summary: "the gating Hydra job is currently failing"
      note: ""
    }
  } else if $gate_ahead and $queues_active {
    {
      state: "draining"
      summary: (
        $"newer gate builds exist, but nixpkgs:unstable still has ($unstable_queue.queued) queued jobset builds and eval ($latest_eval.eval_id) still has ($latest_eval.queued_jobs) queued jobs"
      )
      note: $eval_badge
    }
  } else if $gate_ahead {
    {
      state: "ready-to-publish"
      summary: "the gate is ahead of the published channel and the obvious queues look clear"
      note: $eval_badge
    }
  } else if $queues_active {
    {
      state: "building"
      summary: "the published channel matches the latest successful gate build, and Hydra is already building newer unstable candidates"
      note: $eval_badge
    }
  } else {
    {
      state: "current"
      summary: "the published channel matches the latest successful gate build"
      note: $eval_badge
    }
  }
}

def print-human [report: record, use_color: bool] {
  let assessment_color = if $report.assessment.state == "blocked" {
    "red_bold"
  } else if $report.assessment.state == "draining" {
    "yellow_bold"
  } else if $report.assessment.state == "ready-to-publish" {
    "cyan_bold"
  } else {
    "green_bold"
  }

  let gate_status = if $report.gate_job.current_failed { "failing" } else { "green" }
  let gate_status_color = if $report.gate_job.current_failed { "red_bold" } else { "green" }
  let published_matches_repo = ($report.repo_pin.short_revision == $report.published.short_revision)
  let repo_fragment = if $published_matches_repo {
    ""
  } else {
    $" -> published ($report.published.short_revision)"
  }

  print $"nixpkgs-unstable: (colorize ($report.assessment.state | str replace '-' ' ') $assessment_color $use_color)"
  print $"  assessment: ($report.assessment.summary)"
  if ($report.assessment.note | default "") != "" {
    print $"  eval note:  ($report.assessment.note)"
  }
  print $"  repo pin:   ($report.repo_pin.ref)@($report.repo_pin.short_revision)($repo_fragment)"
  print $"  published:  ($report.published.release_name) @ ($report.published.short_revision)"
  print $"              released ($report.published.released_at) via eval ($report.published.eval_id)"
  print $"  gate job:   (colorize $gate_status $gate_status_color $use_color), latest ($report.gate_job.latest_status | str downcase) build ($report.gate_job.latest_build_id)"
  print $"              ($report.gate_job.latest_release_name) finished ($report.gate_job.latest_finished_at)"
  if $report.gate_job.queued_builds > 0 {
    let queued_candidate = $report.gate_job.newest_queued_candidate
    if $queued_candidate == null {
      print $"  gate queue: ($report.gate_job.queued_builds) queued gate build(s)"
    } else {
      print $"  gate queue: ($report.gate_job.queued_builds) queued; newest visible candidate ($queued_candidate.release_name) queued ($queued_candidate.queued_at)"
    }
  }
  print $"  latest eval: ($report.latest_eval.eval_id) on ($report.latest_eval.started_at) @ ($report.latest_eval.short_revision)"
  print $"               queued=($report.latest_eval.queued_jobs), still-failing=($report.latest_eval.still_failing_jobs), newly-failing=($report.latest_eval.newly_failing_jobs), timed-out=($report.latest_eval.aborted_jobs)"
  print $"  unstable q: ($report.unstable_queue.queued) queued in nixpkgs:unstable"
  print $"              oldest ($report.unstable_queue.oldest_queued_at), newest ($report.unstable_queue.newest_queued_at)"
  print $"  hydra q:    running=($report.hydra_queue.running), queued=($report.hydra_queue.queued)"
  print "  links:"
  print "    status   https://status.nixos.org/"
  print "    evals    https://hydra.nixos.org/jobset/nixpkgs/unstable/evals"
  print $"    eval     https://hydra.nixos.org/eval/($report.latest_eval.eval_id)"
  print "    gate     https://hydra.nixos.org/job/nixpkgs/unstable/unstable"
  print "    queue    https://hydra.nixos.org/queue-summary"
}

def main [
  --json (-j)
  --no-color
] {
  let use_color = (not $no_color)
  let repo_pin = (load-local-pin)
  let published_html = (fetch-url "https://channels.nixos.org/nixpkgs-unstable")
  let evals_html = (fetch-url "https://hydra.nixos.org/jobset/nixpkgs/unstable/evals")
  let hydra_queue_html = (fetch-url "https://hydra.nixos.org/queue-summary")
  let gate_html = (fetch-url "https://hydra.nixos.org/job/nixpkgs/unstable/unstable")
  let published = (parse-published-channel $published_html)
  let latest_eval_row = (parse-latest-eval-row $evals_html)
  let latest_eval_html = (fetch-url $"https://hydra.nixos.org/eval/($latest_eval_row.eval_id)")
  let eval_summary = (parse-eval-summary $latest_eval_html)
  let gate_metric = (fetch-prometheus-query 'hydra_job_failed{channel="nixpkgs-unstable"}')
  let gate_failed = (($gate_metric.value | get 1) == "1")
  let report = {
    repo_pin: $repo_pin
    published: $published
    latest_eval: ($latest_eval_row | merge $eval_summary)
    gate_job: ({
      current_failed: $gate_failed
    } | merge (parse-gate-job $gate_html))
    unstable_queue: (parse-unstable-queue-row $hydra_queue_html)
    hydra_queue: (parse-hydra-queue $hydra_queue_html)
  }
  let full_report = ($report | upsert assessment (build-assessment $report.published $report.latest_eval $report.gate_job $report.gate_job.current_failed $report.unstable_queue))

  if $json {
    $full_report | to json
  } else {
    print-human $full_report $use_color
  }
}
