"""The settings a repository gives centurion, in its `.ai/cezar/centurion/project.py`:

    from centurion.project import Project

    class MyProject(Project):
        spec_sections = (*Project.spec_sections, "Backward compatibility")
        ui_paths = ("web/src/",)
        rules_file = ".ai/cezar/rules.md"

        def screens_build(self, root):
            subprocess.run(["npm", "run", "build"], cwd=root / "web", check=True)

        def screens_serve_dir(self, root):
            return root / "web" / "dist"

    PROJECT = MyProject()

Only what differs between repositories today is here; the flow itself is fixed.
"""

from pathlib import Path


class NotConfigured(Exception):
    pass


class Project:
    #: Sections every spec must have, matched case-insensitively against "## <section>" (a
    #: heading that contains the word counts: "Decisions" matches "## Decisions and why").
    spec_sections: tuple = ("Goal", "Requirements", "Out of scope", "Decisions")

    #: Path prefixes that count as UI. A plan that names one of them gets mockups, a task whose
    #: diff touches one gets screenshots. Empty: never.
    ui_paths: tuple = ()

    #: The repository's rules every agent reads (spec contents, code conventions, screenshots).
    rules_file: str = "AGENTS.md"

    #: Review rounds per task (and for the plan) before a human is asked.
    max_rounds: int = 3

    def screens_build(self, root: Path) -> None:
        """Build the app for screenshots (skipped when SCREENS_NO_BUILD=1)."""
        raise NotConfigured("this repository has no screenshot app (project.py: screens_build)")

    def screens_serve_dir(self, root: Path) -> Path:
        """The directory of static files to serve for screenshots."""
        raise NotConfigured("this repository has no screenshot app (project.py: screens_serve_dir)")
