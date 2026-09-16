Application.ensure_all_started(:telemetry)
{:ok, _pid} = DomovoyCore.Runtime.start_link(name: DomovoyGitPlugin.Test)
ExUnit.start()
