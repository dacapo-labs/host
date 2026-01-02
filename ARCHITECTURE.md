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

**Skill Format** - Each skill is a markdown file with frontmatter defining model preferences, temperature, and parameters, followed by the prompt template. Skills compose with other skills.

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
├── .config/litellm/config.yaml   # Model routing
├── bin/                          # CLI tools and scripts
├── skills/                       # Local skill library
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
