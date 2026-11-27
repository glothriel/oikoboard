"""Where centurion lives in a repository that uses it. Fixed on purpose: prompts, commands and
the generated workflows all name these paths, so a repository cannot move them."""

# The vendored copy: <HOME>/run.py (entry), <HOME>/project.py (the repository's settings),
# <HOME>/VERSION and <HOME>/centurion/ (this package).
HOME = ".ai/cezar/centurion"
ENTRY = HOME + "/run.py"
PROJECT_FILE = HOME + "/project.py"
VERSION_FILE = HOME + "/VERSION"

# Run state of one workflow run (git-ignored): state.json for the scripts, plus the files the
# agents read and write (current-task.md, review.md, screens/...).
STATE = HOME + "/state"

# The runtime a run uses: the first step of every workflow copies the package, the entry, the
# project settings and the rules file here, and every later step runs this copy. The task loop
# resets the work tree to branches cut from older commits; ignored files survive that, so the
# run keeps executing the code (and prompts) it started with.
RUNTIME = STATE + "/runtime"
RUNTIME_ENTRY = RUNTIME + "/run.py"
PROMPTS = RUNTIME + "/centurion/prompts"
RULES = RUNTIME + "/rules.md"

# The command of the first step (committed entry) and of every later step (the snapshot).
START_CMD = "python3 " + ENTRY
CMD = "python3 " + RUNTIME_ENTRY

WORKFLOWS = ".ai/cezar/workflows"
WORKFLOW_PREFIX = "centurion-"
SPECS = ".ai/specs"
TASKS_GLOB = SPECS + "/*.tasks.md"
AGENTIC_CONFIG = ".ai/agentic.config.json"

# Branches and labels.
FEATURE = "feature/issue-{n}"
PLAN_BRANCH = "centurion/issue-{n}-plan"
TASK_BRANCH = "centurion/issue-{n}-{task}"
SCREENS_BRANCH = "centurion-screens/issue-{n}"
MOCKUPS_BRANCH = "centurion-mockups/issue-{n}"

LABEL_AGENT = "agent"
LABEL_PLAN = "stage:plan"
LABEL_FINAL = "stage:final"
LABEL_HUMAN = "needs-human"
LABEL_RESUME = "resume"
