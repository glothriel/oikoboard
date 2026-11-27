"""centurion settings for oikoboard (see centurion/project.py for every setting).

After changing this file run `python3 .ai/cezar/centurion/run.py generate` and commit the workflows."""

import subprocess

from centurion.project import Project


class Oikoboard(Project):
    spec_sections = ("Goal", "Requirements", "Out of scope", "Decisions", "Backward compatibility")
    # A plan naming, or a task touching, the Flutter app's code gets mockups / screenshots.
    ui_paths = ("app/lib/",)
    rules_file = ".ai/cezar/rules.md"

    def screens_build(self, root):
        # the web app on the in-memory mock backend: no server needed
        subprocess.run(["flutter", "build", "web", "--dart-define=OIKO_API=mock"], cwd=root / "app", check=True,
                       stdout=subprocess.DEVNULL)

    def screens_serve_dir(self, root):
        return root / "app" / "build" / "web"


PROJECT = Oikoboard()
