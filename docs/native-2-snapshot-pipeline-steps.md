# Snapshot Pipeline — Owner Steps (M1 Task 5)

Goal: leaderboards compute automatically. ~10 minutes in the Supabase dashboard.
Never paste the worker secret into chat, git, or the app.

## 1. Mint the worker secret
- [ ] In a local terminal: `openssl rand -hex 32` — this is SNAPSHOT_WORKER_SECRET.
- [ ] Dashboard → Edge Functions → Secrets → add `SNAPSHOT_WORKER_SECRET` = that value.
- [ ] Dashboard → Project Settings → Vault → New secret: name `snapshot_worker_secret`,
      value = the SAME string.

## 2. Enable extensions + schedule (SQL Editor, one paste)
- [ ] Run:
      create extension if not exists pg_cron;
      create extension if not exists pg_net;

      select cron.schedule(
        'teecircle-enqueue-snapshots',
        '* * * * *',
        $$select public.enqueue_missing_trip_snapshot_jobs_service_v1();$$
      );

      select cron.schedule(
        'teecircle-recompute-snapshots',
        '* * * * *',
        $$
        select net.http_post(
          url := 'https://zgrbwhnfuxgvkwtgrncu.supabase.co/functions/v1/recompute-trip-snapshot-v1',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-tee-circle-worker-secret',
            (select decrypted_secret from vault.decrypted_secrets
             where name = 'snapshot_worker_secret')
          ),
          body := '{}'::jsonb
        );
        $$
      );

## 3. Verify (after ~2 minutes)
- [ ] SQL Editor: `select jobid, jobname, schedule, active from cron.job;`
      → both teecircle-* jobs listed, active = t.
- [ ] Score a hole in the app, wait 2 minutes, then:
      `select trip_id, revision, generated_at from public.trip_leaderboard_snapshots order by generated_at desc limit 3;`
      → a row with a recent generated_at.
- [ ] In the app: Leaderboard tab shows standings with a REVISION number.
