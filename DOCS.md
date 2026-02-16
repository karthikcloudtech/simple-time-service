# Documentation Map

Quick guide to understanding this repository from any entry point.

## Start Here (Pick Your Path)

### 🚀 **I want to run this locally RIGHT NOW**
→ Go to [QUICK_START.md](QUICK_START.md)
- Copy-paste commands to start the app
- See what endpoints are available
- Test with `curl`

### 📚 **I want to understand what this service does**
→ Start with [README.md](README.md)
- What the service does (in 4 bullet points)
- Key features and endpoints
- Configuration options
- How to deploy with Docker/Kubernetes

### 🏗️ **I want the complete architecture picture**
→ Read [ARCHITECTURE.md](ARCHITECTURE.md)
- System architecture diagram
- Data flow through the system
- Application internals (files and responsibilities)
- Deployment options (local, Docker, Kubernetes)
- Why certain design decisions were made

### 🔧 **I want infrastructure & deployment details**
→ Check [docs/infrastructure/](docs/infrastructure/)
- EKS cluster setup
- Monitoring and logging
- DNS, secrets, troubleshooting

---

## Document Summary

| Document | Size | Purpose | Best For |
|----------|------|---------|----------|
| **[QUICK_START.md](QUICK_START.md)** | 217 lines | Getting started fast | Developers, testing locally |
| **[README.md](README.md)** | 320 lines | Feature documentation | Understanding the app |
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | 530 lines | Complete system design | Architects, understanding design |
| **[docs/infrastructure/](docs/infrastructure/)** | 8 files | Deployment guides | DevOps, production setup |

---

## The Three-Level Approach

### Level 1: Quick Start (15 minutes)
1. Read the first section of [QUICK_START.md](QUICK_START.md)
2. Run: `python3 app/app.py`
3. Test: `curl http://localhost:8080/`
4. Done! You're running the service.

### Level 2: Understanding (30 minutes)
1. Read [README.md](README.md) - Features and endpoints
2. Understand the graceful degradation model
3. Look at environment variables section
4. See the troubleshooting examples

### Level 3: Deep Dive (1-2 hours)
1. Study [ARCHITECTURE.md](ARCHITECTURE.md) sections:
   - System Architecture
   - Data Flow
   - Application Architecture
2. Examine `app/` source code
3. Understand deployment options
4. Read about design decisions

---

## Quick Answers

**Q: How do I run this locally?**
A: `python3 app/app.py` → See [QUICK_START.md](QUICK_START.md)

**Q: What happens if Kafka is down?**
A: App still works, events just aren't sent → See [README.md](README.md#how-it-works)

**Q: How is data persisted?**
A: Kafka → Background Consumer → SQLite → See [ARCHITECTURE.md](ARCHITECTURE.md#data-flow)

**Q: How do I deploy to Kubernetes?**
A: See [docs/infrastructure/SETUP.md](docs/infrastructure/SETUP.md)

**Q: Can I modify the code?**
A: Yes! Edit `app/app.py` and run locally → See [README.md](README.md#contributing)

**Q: What's the project structure?**
A: See [README.md](README.md#project-structure) or [ARCHITECTURE.md](ARCHITECTURE.md#file-structure--responsibilities)

**Q: Why 60% Kafka code reduction?**
A: Removed unnecessary complexity → See [README.md](README.md#simplification--code-quality)

---

## File Organization

```
Root Documentation (High-level overview):
├── README.md           ← Features, endpoints, local development
├── QUICK_START.md      ← Get running in 5 minutes
├── ARCHITECTURE.md     ← System design, data flow, deployment
└── This File           ← Navigation guide

Application Code:
├── app/
│   ├── app.py          ← Flask application (370 lines)
│   ├── kafka_config.py
│   ├── kafka_producer.py
│   ├── kafka_consumer.py
│   └── database.py
├── Dockerfile
└── requirements.txt

Infrastructure (Deployment & Operations):
└── docs/infrastructure/
    ├── README.md
    ├── SETUP.md                    ← EKS setup
    ├── MONITORING_ACCESS.md        ← Observability
    ├── SECRETS_MANAGEMENT.md
    ├── DNS_SETUP.md
    ├── PROJECT_STRUCTURE.md
    ├── TROUBLESHOOTING_AWS_LB_CONTROLLER.md
    └── IAM_ROLE_ANNOTATION_FIX.md
```

---

## Key Concepts

**Graceful Degradation**
- App prioritizes availability over completeness
- If optional services (Kafka, DB, monitoring) fail, app still works
- Requests always return 200 OK (unless app crashes, which it won't)
- See [ARCHITECTURE.md](ARCHITECTURE.md#why-graceful-degradation)

**Event-Driven Persistence**
- HTTP requests generate events
- Events flow through Kafka (fire-and-forget, ~1ms)
- Background consumer writes events to SQLite
- DB queries can generate analytics/reports
- See [ARCHITECTURE.md](ARCHITECTURE.md#why-event-driven-persistence-kafka--sqlite)

**Multi-Stage Docker Build**
- Reduces image size from 500MB → 120MB
- Faster deployments, better security
- See [README.md](README.md#why-multi-stage-docker-build)

---

## Recommended Reading Order

**For Quick Start:**
1. This file (you're reading it)
2. [QUICK_START.md](QUICK_START.md) - Get it running
3. [README.md](README.md) - Understand features
4. Done! Start hacking

**For Production Setup:**
1. [README.md](README.md) - Understand the app
2. [ARCHITECTURE.md](ARCHITECTURE.md) - Understand design
3. [docs/infrastructure/SETUP.md](docs/infrastructure/SETUP.md) - Deploy to EKS
4. [docs/infrastructure/MONITORING_ACCESS.md](docs/infrastructure/MONITORING_ACCESS.md) - Set up monitoring

**For Understanding Design:**
1. [ARCHITECTURE.md](ARCHITECTURE.md) - All sections
2. Review `app/app.py` source code
3. Check design decision rationales at end of [ARCHITECTURE.md](ARCHITECTURE.md)

---

## One-Page System Overview

```
REQUEST FLOW:
  Client → [Port 8080]
           ↓
       Flask App
       ├─→ Respond 200 OK (always)
       ├─→ Send events to Kafka (optional, fire-and-forget)
       ├─→ Record metrics (optional)
       └─→ Trace request (optional)
           ↓
       Kafka Topic (if available)
           ↓
       Consumer (background thread)
           ├─→ Read events from Kafka
           └─→ Insert into SQLite database
               (http_requests, http_responses, errors tables)

KEY PRINCIPLE: Core app always works. Optional services degrade gracefully.
```

## Troubleshooting Navigation

| Issue | See |
|-------|-----|
| App won't start | [QUICK_START.md - Troubleshooting](QUICK_START.md#troubleshooting) |
| Kafka issues | [README.md - Troubleshooting](README.md#troubleshooting) |
| Kubernetes deployment | [docs/infrastructure/SETUP.md](docs/infrastructure/SETUP.md) |
| Monitoring not working | [docs/infrastructure/MONITORING_ACCESS.md](docs/infrastructure/MONITORING_ACCESS.md) |
| DNS/SSL issues | [docs/infrastructure/DNS_SETUP.md](docs/infrastructure/DNS_SETUP.md) |
| AWS LoadBalancer issues | [docs/infrastructure/TROUBLESHOOTING_AWS_LB_CONTROLLER.md](docs/infrastructure/TROUBLESHOOTING_AWS_LB_CONTROLLER.md) |

---

**Last Updated:** February 3, 2026  
**Total Documentation:** ~1,400 lines across 3 root files + 8 infrastructure guides (optimized)  
**Removed:** INSTALLATION_BEST_PRACTICES.md (merged into SETUP.md)
