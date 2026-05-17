# Quick Start

Create a workspace:

```sh
mkdir recipe-demo
cd recipe-demo
mentu-recipes init
```

Create `.mentu/recipes/hello.json`:

```json
{
  "name": "hello",
  "description": "A local shell smoke test.",
  "steps": [
    {
      "label": "say-hello",
      "backend": "shell",
      "prompt": "echo MENTU_RECIPES_COMPLETE",
      "completion_keyword": "MENTU_RECIPES_COMPLETE"
    }
  ]
}
```

Validate it:

```sh
mentu-recipes check hello
```

Run it:

```sh
mentu-recipes run hello --no-cloud
```

After the run, inspect the local record:

```sh
find .mentu/runs -maxdepth 3 -type f
```

You should see a `run.json` file plus step output files.
