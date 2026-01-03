# Personal AI Control Center

Built on the principles of [PAI (Personal AI Infrastructure)](https://github.com/danielmiessler/PAI) by Daniel Miessler.

## Foundational Pattern

Every task follows two nested loops:

**Outer Loop:** Current State → Desired State. The gap you're closing.

**Inner Loop:** OBSERVE → THINK → PLAN → BUILD → EXECUTE → VERIFY → LEARN. The scientific method applied to each iteration.

Verifiability is everything. If you cannot measure whether you reached the desired state, you are guessing.

## Stack

**Host** - Terraform-provisioned EC2 with Tailscale-only access, LUKS encryption, and Bitwarden for secrets. The always-available foundation.

**CLIProxyAPI** - Wraps AI CLI tools (Gemini, Claude Code, Codex) and exposes them as standard APIs. Enables programmatic access to paid subscriptions without API keys.

**LiteLLM** - Unified interface to all AI models. Configured via YAML. Routes to direct APIs, cloud providers (Bedrock, Vertex), or CLIProxyAPI. Scaffolding over model choice.

**Skills** - Markdown files containing prompts, model preferences, and workflow definitions. Modular, routable capabilities for personalization.

**SkillsMP** - Marketplace cache for discovering and installing community skills not available locally. Expands capabilities without reinventing.

**Scripts** - Simple utilities in ~/bin that load skills and call LiteLLM. CLI as interface.

## Access Paths

| Method | Auth | Use Case |
|--------|------|----------|
| Direct API | API keys from Bitwarden | Pay-per-token |
| Bedrock/Vertex | AWS/GCP credentials | Cloud billing |
| CLIProxyAPI | OAuth via CLI tools | Existing subscriptions |

## Unified Multi-Model Access

LiteLLM's batch_completion enables parallel queries to multiple models. CLIProxyAPI exposes subscription-based CLI tools as standard API endpoints. Combined, fanout works identically across any model regardless of authentication method.

A single call can query Gemini through your Google subscription, Claude through your Anthropic subscription, and GPT-4 through an API key simultaneously. LiteLLM routes each request appropriately. The caller does not know or care which auth method each model uses.

## Skills Architecture

**Model Agnostic** - Skills are written to work with any model. The prompt content does not assume a specific provider. Model selection happens at runtime through LiteLLM routing, not within the skill itself. This allows the same skill to run on Claude, GPT, Gemini, or any other model without modification.

**Cross-Platform Compatibility** - Major AI platforms have adopted the skills pattern but use different filenames. Claude uses CLAUDE.md, Codex uses AGENTS.md, Gemini uses GEMINI.md. The underlying format is similar. SkillsMP normalizes these differences, allowing skills from any source to be discovered and used regardless of original naming convention.

**Local Skills** - Personal prompts and workflows in ~/skills organized by domain. Version controlled. Continuously refined.

**SkillsMP Cache** - Cached index of marketplace skills with search, scoring, and metadata. Skills are evaluated by author trust, community rating, and relevance before use.

## Skill Format

Adopts the Agent Skills open standard from agentskills.io with Fabric pattern conventions for the body.

**Directory Structure:**
```
skill-name/
├── SKILL.md              # Required - metadata and instructions
├── scripts/              # Optional - automation scripts
├── references/           # Optional - context documents
└── assets/               # Optional - supporting files
```

**SKILL.md Format:**
```yaml
---
name: summarize                    # Required: 1-64 chars, lowercase, hyphens only
description: |                     # Required: 1-1024 chars
  Summarize any content into key points with actionable takeaways
license: MIT                       # Optional: license name or file reference
compatibility: claude, gpt, gemini # Optional: tested models
allowed-tools: read_file           # Optional: pre-approved tools for this skill
metadata:
  scope: read-only                 # read-only | reversible | destructive
  temperature: 0.3                 # model parameter defaults
  max_tokens: 2000
  tags: [writing, analysis]
---

# IDENTITY and PURPOSE

You are an expert content summarizer...

# STEPS

1. Read the input content carefully
2. Identify the main themes...

# OUTPUT INSTRUCTIONS

- Use markdown formatting
- Keep summary under 500 words...
```

**Scope Declaration** - Every skill declares its scope in metadata. The agent loop enforces this. If a skill with read-only scope attempts to call a destructive tool, the action is blocked.

**Tool Permissions** - The allowed-tools field lists tools the skill may use. Tools not listed are blocked. This provides defense in depth beyond scope classification.

## Meta-Skills

Some skills orchestrate other skills rather than performing direct work.

### Swarm

Runs a skill in parallel across multiple inputs, then synthesizes results. Uses LiteLLM's batch_completion for parallel execution.

**Use cases:**
- Research multiple topics simultaneously
- Compare multiple options
- Multi-source verification
- Parallel data gathering

**How it works:**
1. Receive base skill and list of inputs
2. Run base skill against each input in parallel
3. Collect all results
4. Synthesize into unified output

**Example:**
```
swarm --skill researcher --inputs "OpenAI,Anthropic,Google,Meta,Mistral"
```

Spawns 5 parallel researcher invocations, each targeting one company. Results are synthesized into a single comparative report.

**Scope:** Inherits from base skill. If base skill is read-only, swarm is read-only.

### Meta-Prompt

Generates optimized prompts dynamically based on task analysis. Rather than using static prompts, meta-prompt analyzes the request and constructs a context-aware prompt.

**Use cases:**
- Transform vague requests into precise prompts
- Inject relevant context automatically
- Adapt prompts to specific models
- Improve prompt quality iteratively

**How it works:**
1. Receive task description and context
2. Analyze task requirements and constraints
3. Select appropriate prompt structure
4. Inject zone context, preferences, and history
5. Generate optimized prompt for target model

**Example:**
```
Input: "summarize this article"
Meta-Prompt generates:
  "You are an expert content analyst specializing in extracting
   actionable insights. Given the following article, identify the
   thesis, three key supporting arguments, and practical takeaways.
   Format as bullet points under 200 words. Article: {content}"
```

**Context injection includes:**
- Zone preferences (output format, verbosity)
- Session history (prior conversation)
- Model capabilities (what this model does well)
- User patterns (learned preferences)

**Scope:** Read-only. Generates prompts, does not execute them.

### Chain

Decomposes complex requests into a sequence of skills executed in order. Output from each skill feeds into the next.

**Use cases:**
- Multi-step workflows
- Research → analysis → report pipelines
- Data gathering → processing → output
- Any task requiring ordered steps

**How it works:**
1. Receive complex task description
2. Decompose into ordered skill sequence
3. Execute skills sequentially
4. Pass output from each to the next
5. Return final result

**Example:**
```
chain --task "research competitors and write summary report"
```

Decomposes to:
1. researcher skill → gather competitor data
2. analyzer skill → compare and contrast
3. writer skill → produce formatted report

**Scope:** Inherits highest scope from chain. If any skill is destructive, chain is destructive.

### Refine

Iteratively improves output through self-critique. Generates draft, critiques it, then produces improved version.

**Use cases:**
- High-quality writing
- Code review and improvement
- Analysis refinement
- Any output benefiting from iteration

**How it works:**
1. Generate initial draft using base skill
2. Critique draft against quality criteria
3. Identify specific improvements
4. Generate refined version
5. Optionally repeat for N iterations

**Example:**
```
refine --skill writer --iterations 2 --criteria "clarity,accuracy,conciseness"
```

**Quality criteria options:**
- clarity: Is it easy to understand?
- accuracy: Is it factually correct?
- conciseness: Is it appropriately brief?
- completeness: Does it cover all aspects?
- actionability: Can the reader act on it?

**Scope:** Inherits from base skill.

## Skill Sources

The system draws from established skill libraries rather than reinventing prompts. Community-maintained and vendor-published skills provide tested, refined patterns.

**Fabric Patterns** - Daniel Miessler's pattern library for content analysis, summarization, writing, code explanation, and documentation improvement. The foundation of PAI's skill approach. Available at github.com/danielmiessler/fabric.

**Anthropic Prompt Library** - Official prompts from Anthropic covering business and personal tasks including code consulting, writing assistance, data analysis, and creative work. Optimized for Claude models. Available at docs.anthropic.com/en/prompt-library.

**OpenAI Cookbook** - Examples and guides for GPT models including agentic prompting, multi-tool orchestration, and specialized workflows. Continuously updated with new model releases. Available at cookbook.openai.com.

**Google Prompt Gallery** - Official Gemini examples for multimodal tasks, structured output, teaching, and code generation. Available at ai.google.dev/gemini-api/prompts.

**Agent Skills** - Open standard originally developed by Anthropic for extending agent capabilities. Structured folders of instructions, scripts, and resources that agents discover and use. Supported by Claude, OpenAI, Cursor, GitHub, and VS Code. Available at agentskills.io.

**SkillsMP** - Aggregated marketplace caching skills from multiple sources with search, scoring by author trust and community rating, and local installation.

## Directory Structure

```
~/
├── .config/
│   ├── litellm/config.yaml       # Model routing
│   └── zones/                    # Zone configurations
│       ├── work/CLAUDE.md
│       ├── personal/CLAUDE.md
│       └── projects/*/CLAUDE.md
├── bin/                          # CLI tools and scripts
├── skills/                       # Local skill library
│   └── skill-name/
│       ├── SKILL.md              # Required
│       ├── scripts/              # Optional
│       └── references/           # Optional
├── sessions/                     # Session state and history
│   ├── active/                   # Currently running
│   │   └── {id}/
│   │       ├── meta.json
│   │       ├── context.json
│   │       ├── log.jsonl
│   │       └── state.json
│   ├── paused/                   # Suspended
│   └── archive/                  # Completed
├── log/                          # Daily notes and outputs
└── .cache/skillsmp/              # Marketplace skill cache
```

## Principles

Derived from PAI's 15 founding principles:

1. **Verifiable Outcomes** - Every action has measurable success criteria
2. **Scaffolding Over Model** - Architecture matters more than which AI you use
3. **Code Before Prompts** - Automate routine tasks; reserve AI for complex work
4. **UNIX Philosophy** - Modular tools that do one thing well and compose easily
5. **CLI as Interface** - Command-line tools are faster and more scriptable than GUIs
6. **Deterministic Design** - Consistent patterns, not randomness
7. **Custom Skill Management** - Modular, routable capabilities for personalization
8. **Configuration Over Code** - YAML and Markdown define behavior; code executes
9. **Persistent Context** - Capture everything worth knowing for future reference
10. **Self-Updating Systems** - Infrastructure that improves through use

## Zero Friction

The system eliminates barriers between intent and action. Resources are always available, authentication is invisible, and manual intervention is avoided.

**Always Available** - The host runs continuously. Tailscale provides instant access from any device. Credentials are cached and refreshed automatically. There is no startup time, no login ritual, no waiting.

**Invisible Authentication** - Bitwarden supplies secrets on demand. CLIProxyAPI maintains OAuth sessions. LiteLLM routes to whichever provider is authenticated. The user never types a password or refreshes a token during normal operation.

**No User Interaction** - Workflows run to completion without prompts or confirmations. Skills define all parameters upfront. Scripts handle errors and retry automatically. Human attention is reserved for decisions that require judgment, not for babysitting processes.

## Guardrails

Zero friction does not mean zero safety. AI actions that could cause data loss or irreversible changes require explicit gates.

**Action Classification** - Every operation is classified as read-only, reversible, or destructive. Read-only actions execute freely. Reversible actions proceed with logging. Destructive actions require confirmation or are blocked entirely.

**Pre-Execution Validation** - Before any file modification, deletion, or external mutation, the system validates intent against defined boundaries. Skills declare their maximum scope. Scripts cannot exceed what the skill permits.

**Dry Run by Default** - Destructive operations preview their effects before execution. The user sees what will change and explicitly approves. This is the one exception to no user interaction: irreversible actions always pause.

**Audit Trail** - All AI-initiated actions are logged with timestamp, skill invoked, parameters used, and outcome. If something goes wrong, the log shows exactly what happened and why.

## Sessions

All activity occurs within sessions. Sessions provide context boundaries, state persistence, and audit scope. Guardrails and dry runs apply at the session level.

## Session Hierarchy

Sessions are compositional. Zone provides the foundation. Work and Agent sessions run within a zone and contain model memory.

**Zone Session** - The context layer. Provides credentials scope, guardrail settings, model preferences, and permission boundaries. Work zone, personal zone, project-specific zones. Switching zones switches context entirely. No bleed between domains.

## Zone Configuration

Zones adopt CLAUDE.md conventions. Each zone is a directory containing a CLAUDE.md file with zone-specific context and settings.

**Directory Structure:**
```
~/.config/zones/
├── work/
│   ├── CLAUDE.md           # Zone context and rules
│   └── @imports/           # Shared config fragments
├── personal/
│   └── CLAUDE.md
└── projects/
    └── client-a/
        └── CLAUDE.md
```

**Zone CLAUDE.md Format:**
```markdown
# Work Zone

## Purpose
Corporate development work for Acme Corp.

## Credentials
- AWS Profile: work-account
- Bitwarden Folder: work

## Guardrails
- destructive: require-approval
- reversible: log-only
- read-only: allow

## Model Preferences
- Default: claude-3-opus
- Fast: claude-3-haiku
- Code: claude-3-opus

## Allowed Skills
@imports/standard-skills.md

## Blocked Skills
- personal/*
- experimental/*

## Notifications
- approval-channel: slack
- alert-channel: email
```

**Zone Discovery** - Zones are discovered recursively from ~/.config/zones. Nested zones inherit from parents and can override settings.

**Zone Switching** - Active zone is set via environment variable or command. All sessions within a zone inherit its context. Switching zones switches credentials, permissions, and model preferences entirely.

**Model Session** - Conversation memory within a zone. Prior exchanges inform current responses. Context is persisted to disk and reloaded on resume. Token limits are managed by summarization or sliding window. Model sessions are contained within work or agent sessions.

**Work Session** - Human-driven activity within a zone. Starting a session creates a boundary. Everything within it shares state, history, and logging. Contains one or more model sessions. Stop the session and context is saved. Resume later and pick up where you left off.

**Agent Session** - Autonomous background task within a zone. Starts with a goal and skill, runs independently, reports when complete. Contains its own model session. Model-agnostic using LiteLLM. State persists across interruptions. Multiple agent sessions can run concurrently.

Both work and agent sessions inherit zone context and maintain their own model memory. A work session in your personal zone uses personal credentials and personal guardrails. An agent session in your work zone uses work credentials and work guardrails.

## Agent Loop

Following PAI's "Scaffolding > Model" principle, agents use a minimal loop that works with any model:

The loop receives a goal, repeatedly calls the model through LiteLLM, executes any requested tools, adds results to context, and continues until the goal is achieved or the agent determines it cannot proceed. Every iteration is logged. Every tool execution passes through guardrails.

Agent sessions inherit the guardrail settings of their parent zone. Destructive actions trigger dry run and require approval unless the zone explicitly permits autonomous execution. Read-only and reversible actions proceed with logging.

The agent loop is intentionally simple. No framework, no complex orchestration. A script of approximately fifty lines that calls LiteLLM, handles tools, and logs everything. If a better standard emerges, it can be swapped without architectural change.

## Session Lifecycle

**Start** - Session begins with explicit start or implicit first action. Context is initialized. Zone settings are loaded. Logging begins.

**Active** - Actions execute within session context. Model calls include session history. Tools execute with session-scoped permissions. All activity is logged to session-specific files.

**Pause** - Session state is serialized to disk. Can occur explicitly or on connection drop. No data loss.

**Resume** - State is restored from disk. Context is reloaded. Work continues from pause point.

**End** - Session completes. Final state is logged. Summary is generated. Artifacts are indexed for future reference.

## Session State Format

Each session is stored as a directory with structured files.

**Session Directory:**
```
~/sessions/active/abc123/
├── meta.json           # Session metadata
├── context.json        # Model conversation memory
├── log.jsonl           # Append-only event log
└── state.json          # Current working state
```

**meta.json:**
```json
{
  "id": "abc123",
  "type": "work",
  "zone": "personal",
  "started": "2025-01-02T10:30:00Z",
  "status": "active",
  "skill": "code-review",
  "goal": "Review PR #42"
}
```

**log.jsonl:** (append-only, one JSON object per line)
```json
{"ts": "2025-01-02T10:30:01Z", "event": "session_start", "zone": "personal"}
{"ts": "2025-01-02T10:30:05Z", "event": "skill_invoke", "skill": "code-review"}
{"ts": "2025-01-02T10:30:10Z", "event": "tool_exec", "tool": "read_file", "params": {"path": "/src/main.py"}, "result": "success"}
{"ts": "2025-01-02T10:31:00Z", "event": "guardrail", "action": "write_file", "classification": "reversible", "decision": "allow"}
```

**context.json:** Model conversation memory using sliding window. Last N messages retained. Older messages summarized or dropped based on zone token settings.

**state.json:** Skill-specific working state. Contents vary by skill. Serialized on pause, restored on resume.

## Token Management

Model sessions use sliding window by default. Configurable per zone.

**Sliding Window (Default):**
- Retain last N messages (default: 20)
- Drop oldest messages when limit exceeded
- Simple, predictable, no summarization latency

**Summarization (Optional):**
- When context exceeds threshold, summarize older messages
- Summary replaces original messages
- Preserves more context at cost of latency
- Enable per zone: `token_management: summarize`

**Token Limits:**
```markdown
## Token Settings
- context_limit: 20000          # Max tokens before management kicks in
- sliding_window_messages: 20   # Messages to retain in sliding window
- summarize_threshold: 15000    # Trigger summarization at this level
- summarize_target: 5000        # Compress to this size
```

## Session Guardrails

Guardrails are evaluated at session scope:

**Inherited Permissions** - Sessions inherit the guardrail settings of their zone. A work zone may permit more autonomous action than a personal zone. A high-trust project zone may allow destructive actions that a new project zone would block.

**Escalation Path** - When an action exceeds session permissions, the session pauses and requests approval. Approval can come interactively or via configured notification channel. Denied actions are logged and the session continues with alternative approach.

## Notification Channels

Approval requests and alerts are delivered through configured channels. Zones specify which channels to use.

**Supported Channels:**
- **stdout** - Interactive terminal prompt. Used for work sessions with attached terminal.
- **file** - Write to approval queue file. Check manually when convenient.
- **ntfy** - Push notification via ntfy.sh. Mobile-friendly, self-hostable.
- **pushover** - Push notification via Pushover. Mobile apps for iOS/Android.
- **slack** - Message to Slack channel or DM. Good for work zones.
- **email** - Email notification. Good for non-urgent approvals.
- **sms** - SMS via Twilio. Good for urgent approvals.

**Approval Flow:**
1. Agent session encounters destructive action
2. Dry run preview is generated and logged
3. Notification sent to configured channel with preview and approve/deny options
4. Session waits for response (with configurable timeout)
5. On approval: action executes, logged with approver
6. On denial: action skipped, session continues with alternative
7. On timeout: action skipped, session logs timeout

**Dry Run Integration** - Before any destructive action, the session generates a preview. In interactive sessions, the preview is shown immediately. In agent sessions, the preview is logged and the action waits for approval unless pre-authorized.

**Session Audit** - Complete session history is retained. Every model call, tool execution, decision point, and outcome. Sessions can be replayed for debugging or review. Audit logs are append-only and tamper-evident.

## Logging

Following "Code Before Prompts," logging leverages LiteLLM's built-in observability rather than reinventing it.

**LiteLLM Handles** - Model calls, input/output, token counts, cost per request, latency, provider tracking, success/failure events, streaming events. LiteLLM normalizes this across all providers and integrates with observability platforms like Langfuse, Datadog, and PostHog.

**Session Layer Adds** - Tool executions with parameters and results. Session lifecycle events including start, pause, resume, and end. Guardrail decisions showing action classification, approvals, and denials. Dry run previews generated. Skill invocations with source and outcome. Zone transitions. Approval requests and responses.

**Log Structure** - Each session writes to its own log file. Model call logs flow through LiteLLM callbacks. Session events append to session-specific logs. All logs include timestamps, session ID, and zone context. Logs are append-only for tamper evidence.

**Sensitive Data** - Credentials and secrets are never logged. Input content can be hashed instead of stored verbatim when privacy is required. LiteLLM supports redaction for API keys. Zone configuration determines logging verbosity.

## Scheduled Agents

Agents run on a daily schedule via cron. Global agents run once. Per-zone agents run for each configured zone. All operate within guardrails and produce reports for human review before any changes are applied.

### Global Agents

#### Researcher (External)

Runs once daily to scan the AI ecosystem for improvements.

**Goal:** Find new developments in AI tooling, prompting techniques, model capabilities, and agent patterns that could benefit the system.

**Sources:**
- PAI repository updates and discussions
- Agent Skills registry for new skills
- Fabric patterns for new prompts
- Model provider changelogs and documentation
- AI research and tooling communities

**Output:** ~/log/research/{date}.md containing:
- New techniques discovered
- Relevant new skills or patterns
- Model capability updates
- Suggested improvements with rationale
- Links to sources

**Scope:** Read-only. Gathers and reports. Does not modify the system.

### Per-Zone Agents

Each zone runs its own set of agents. Zone isolation is maintained. Work zone agents only see work sessions.

#### Researcher (Internal)

Runs daily per zone to capture knowledge from zone activity.

**Goal:** Index artifacts, learnings, and patterns from zone sessions. Combine with global research for zone-specific relevance.

**Inputs:**
- Global research report
- Zone session logs and outputs
- Zone artifacts and notes

**Output:** ~/log/{zone}/knowledge/{date}.md containing:
- Zone-specific learnings indexed
- Global research filtered for zone relevance
- Patterns identified from zone work
- Knowledge base updates

**Scope:** Read-only. Indexes and reports. Knowledge stays local, not fed to AI.

#### Healer

Runs daily per zone to maintain zone health.

**Goal:** Review zone state, identify issues, propose fixes while maintaining PAI principles.

**Inputs:**
- Zone session logs from past 24 hours
- Zone error logs and failures
- Guardrail denials and escalations
- Zone researcher report

**Analysis:**
- Identify recurring errors or failures
- Detect guardrail patterns suggesting misconfiguration
- Check for skill or zone configuration issues
- Assess resource usage and performance

**Output:** ~/log/{zone}/health/{date}.md containing:
- Zone health summary
- Issues identified with severity
- Proposed fixes with dry run previews
- Alignment check against PAI principles

**Scope:** Read-only for analysis. Proposed changes require human approval.

#### Grader

Runs daily per zone to evaluate response quality and skill effectiveness.

**Goal:** Review session transcripts, grade response quality, identify skill improvements.

**Inputs:**
- Zone session transcripts
- Model responses and outcomes
- Skill invocations and results

**Analysis:**
- Score responses on accuracy, helpfulness, efficiency
- Identify weak skills or prompts
- Detect patterns in good vs poor responses
- Track quality trends over time

**Output:** ~/log/{zone}/quality/{date}.md containing:
- Quality scores and trends
- Skill effectiveness ratings
- Suggested skill refinements
- Prompt improvement recommendations

**Scope:** Read-only. Evaluates and reports. Skill changes require human approval.

### Agent Schedule

```
03:00  Global Researcher (external)
04:00  Per-zone Researcher (internal) - all zones
05:00  Per-zone Healer - all zones
06:00  Per-zone Grader - all zones
```

### Workflow

1. Global researcher scans ecosystem → ~/log/research/{date}.md
2. Per-zone researcher indexes zone + reads global research → ~/log/{zone}/knowledge/{date}.md
3. Per-zone healer reviews zone health → ~/log/{zone}/health/{date}.md
4. Per-zone grader evaluates quality → ~/log/{zone}/quality/{date}.md
5. Human reviews reports, approves specific actions
6. Approved changes execute with full logging

### Self-Improvement Loop

```
OBSERVE: Global researcher scans ecosystem
         Per-zone researcher indexes zone work
THINK:   Healer evaluates health against principles
         Grader evaluates quality against standards
PLAN:    Healer proposes fixes
         Grader proposes skill improvements
BUILD:   Dry run previews generated
EXECUTE: Human-approved changes only
VERIFY:  Next day's agents check if changes improved system
LEARN:   Patterns refined, skills updated
```

This implements PAI principle #10 (Self-Updating Systems) while respecting guardrails and human oversight. Knowledge stays local. External research is shared. Zone isolation is maintained.
