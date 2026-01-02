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

**Local Skills** - Personal prompts and workflows in ~/skills organized by domain. Version controlled. Continuously refined.

**SkillsMP Cache** - Cached index of marketplace skills with search, scoring, and metadata. Skills are evaluated by author trust, community rating, and relevance before use.

**Skill Format** - Each skill is a markdown file with frontmatter defining model preferences, temperature, and parameters, followed by the prompt template. Skills compose with other skills.

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
