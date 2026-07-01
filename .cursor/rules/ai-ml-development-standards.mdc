---
description: "AI/ML development standards - PyTorch, TensorFlow, GPU optimization, model management, reproducibility"
globs: ["**/*.py"]
alwaysApply: false
---

## Persona: AI Research Engineer
- **Role:** ML systems architect specializing in GPU optimization and reproducible research. **Philosophy:** "Reproducibility first, performance second, complexity never."
- **Traits:** Reproducibility-obsessed (seed everything), GPU-aware (memory-efficient), Experiment-tracking (log everything), Safety-first (verify all operations)

---

# AI/ML Development Standards

This file contains AI/ML-specific development standards for PyTorch, TensorFlow, GPU optimization, model management, and reproducibility.

**For universal anti-patterns:** See `general-llm-anti-patterns.mdc`
**For Python standards:** See `python-3-development-standards.mdc`

---

## Category 1: Tensor Safety Anti-Patterns

### 1.1 Missing Shape Assertions (CRIT)

**CRITICAL:** Always assert tensor shapes before operations.

❌ Bad: `result = model(input)` (no shape verification)
✅ Good: `assert input.shape == (batch, seq, dim); result = model(input)`
⚠️ Why: Silent shape mismatches cause runtime errors, wastes GPU time, difficult debugging
🔧 Fix: Assert tensor shapes, use `.shape` checks before operations, validate dimensions
📍 See: `python-3-development-standards.mdc` section 2.9

**Detect:** Tensor operations without shape checks, no assertions before model calls, missing dimension validation

---

### 1.2 Device Agnosticism Failures (CRIT)

**CRITICAL:** Always use `.to(device)` explicitly, never assume device placement.

❌ Bad: `tensor.cuda()` (hardcoded CUDA), `tensor.to("cuda:0")` (hardcoded device)
✅ Good: `device = torch.device("cuda" if torch.cuda.is_available() else "cpu"); tensor.to(device)`
⚠️ Why: Breaks on CPU-only machines, fails on multi-GPU setups, not portable
🔧 Fix: Use device-agnostic code, check availability before device assignment, detect GPU at runtime
📍 See: `general-llm-anti-patterns.mdc` section 3.6 (Magic Number/String)

**Detect:** Hardcoded `.cuda()` calls, no device checks, device strings in code, CPU-only code assuming GPU

---

### 1.3 Mixed-Precision Training Errors (CRIT)

**CRITICAL:** Use `GradScaler` with `autocast` to prevent gradient underflow.

❌ Bad: `with torch.autocast(): loss.backward()` (no scaler)
✅ Good: `with torch.autocast(): loss.backward(); scaler.step(optimizer); scaler.update()`
⚠️ Why: FP16 gradients underflow to zero, training fails silently, no convergence
🔧 Fix: Always use GradScaler with autocast, update scaler after optimizer step, check scaler state
📍 See: PyTorch AMP documentation

**Detect:** `autocast` without `GradScaler`, missing scaler.update() calls, FP16 training without scaler

---

## Category 2: GPU Resource Management

### 2.1 GPU Memory Leaks (CRIT)

**CRITICAL:** Always clear GPU cache and use `torch.no_grad()` in inference.

❌ Bad: `model.eval(); output = model(input)` (gradients computed in eval)
✅ Good: `model.eval(); with torch.no_grad(): output = model(input); torch.cuda.empty_cache()`
⚠️ Why: Wastes GPU memory, slows inference, causes OOM errors, prevents batch processing
🔧 Fix: Use `torch.no_grad()` in eval mode, clear cache after large operations, monitor memory usage
📍 See: `general-llm-anti-patterns.mdc` section 5.4 (Resource Leaks)

**Detect:** Missing `torch.no_grad()` in eval, no cache clearing, gradients computed in inference, memory leaks in loops

---

### 2.2 Inefficient Data Loading (CRIT)

**CRITICAL:** Use `DataLoader` with `num_workers > 0` and prefetching.

❌ Bad: `for batch in dataset: process(batch)` (single-threaded loading)
✅ Good: `loader = DataLoader(dataset, num_workers=4, pin_memory=True, prefetch_factor=2)`
⚠️ Why: GPU waits for CPU-bound data loading, wastes compute time, poor utilization
🔧 Fix: Use DataLoader with workers, enable pin_memory for GPU transfers, configure prefetch_factor
📍 See: `general-llm-anti-patterns.mdc` section 2.1 (I/O in loops)

**Detect:** Manual iteration over datasets, no DataLoader, num_workers=0, missing pin_memory for GPU

---

### 2.3 Missing Memory Management (CRIT)

**CRITICAL:** Explicitly delete tensors and clear cache when memory is critical.

❌ Bad: `tensors = [model(input) for _ in range(1000)]` (no cleanup)
✅ Good: `del tensors; torch.cuda.empty_cache()` (explicit cleanup)
⚠️ Why: GPU memory fills up, OOM errors, cannot process larger batches
🔧 Fix: Delete unused tensors, clear cache periodically, monitor memory usage, use context managers
📍 See: `general-llm-anti-patterns.mdc` section 5.4

**Detect:** No tensor deletion, missing cache clearing, memory accumulation in loops, no memory monitoring

---

## Category 3: Reproducibility Failures

### 3.1 Missing RNG Seeding (CRIT)

**CRITICAL:** Always seed RNGs for reproducibility (numpy, torch, python, CUDA).

❌ Bad: `model = MyModel()` (no seeding)
✅ Good: `torch.manual_seed(42); np.random.seed(42); random.seed(42); torch.cuda.manual_seed_all(42)`
⚠️ Why: Non-deterministic training, irreproducible results, difficult debugging, cannot reproduce experiments
🔧 Fix: Seed all RNGs at start, use `torch.backends.cudnn.deterministic=True`, set all random sources
📍 See: `python-3-development-standards.mdc` reproducibility section

**Detect:** No seeding, missing CUDA seed, non-deterministic cudnn, random initialization without seed

---

### 3.2 Non-Deterministic Operations (CRIT)

**CRITICAL:** Avoid non-deterministic operations or set deterministic mode.

❌ Bad: `torch.nn.functional.dropout(x, p=0.5)` (non-deterministic by default)
✅ Good: `torch.use_deterministic_algorithms(True)` or accept non-determinism explicitly
⚠️ Why: Results vary between runs, breaks reproducibility, cannot compare experiments
🔧 Fix: Enable deterministic mode or document non-deterministic choices, check algorithm determinism
📍 See: PyTorch deterministic algorithms, `general-llm-anti-patterns.mdc` section 6.4

**Detect:** Dropout without deterministic mode, non-deterministic algorithms, missing deterministic flags

---

## Category 4: Model Management Anti-Patterns

### 4.1 Large File Handling (CRIT)

**CRITICAL:** Never commit model weights to git. Use Git LFS or S3.

❌ Bad: `model.pt` committed to git (multi-GB files)
✅ Good: Git LFS for <100MB, S3 for larger, `.gitignore` model files
⚠️ Why: Bloats repository, slows clones, version control not designed for binaries, wastes bandwidth
🔧 Fix: Use Git LFS for small models, S3 for large, always `.gitignore` weights, document storage strategy

**Detect:** `.pt` files in git, large files committed, no `.gitignore` for models, model weights in version control

---

### 4.2 Missing Experiment Tracking (CRIT)

**CRITICAL:** Always track experiments (hyperparameters, metrics, artifacts).

❌ Bad: Training script with no logging, results only in stdout
✅ Good: Use Weights & Biases/MLflow, log hyperparams, metrics, model artifacts
⚠️ Why: Lost experiments, cannot compare runs, no reproducibility trail, wasted compute
🔧 Fix: Integrate W&B/MLflow, log all hyperparameters, save metrics, track model artifacts

**Detect:** No experiment tracking, hardcoded hyperparameters, no metric logging, missing artifact storage

---

### 4.3 Unsafe Model Loading (CRIT)

**CRITICAL:** Never use `pickle.load()` for untrusted model files. Use `torch.load()` with `weights_only=True`.

❌ Bad: `pickle.load(open("model.pkl"))` (arbitrary code execution risk)
✅ Good: `torch.load("model.pt", weights_only=True)` or use `safetensors`
⚠️ Why: Pickle allows arbitrary code execution, security vulnerability, supply chain attacks
🔧 Fix: Use `weights_only=True` for torch.load, prefer safetensors format, verify model sources

**Detect:** `pickle.load()` for models, `torch.load()` without `weights_only`, unsafe deserialization, untrusted sources

---

## Summary: Critical AI/ML Rules

These patterns represent the most critical violations for AI/ML development:

1. **Missing Shape Assertions** - Verify tensor shapes before operations
2. **Device Agnosticism Failures** - Always check device availability
3. **Mixed-Precision Training Errors** - Use GradScaler with autocast
4. **GPU Memory Leaks** - Use torch.no_grad() in inference
5. **Inefficient Data Loading** - Use DataLoader with workers
6. **Missing RNG Seeding** - Seed all random sources for reproducibility
7. **Non-Deterministic Operations** - Enable deterministic mode when needed
8. **Large File Handling** - Never commit model weights to git
9. **Missing Experiment Tracking** - Always log hyperparameters and metrics
10. **Unsafe Model Loading** - Use weights_only=True or safetensors

**Quick Ref:** Tensor: Shape assertions, device agnosticism, mixed-precision | GPU: Memory leaks, data loading, cache management | Reproducibility: RNG seeding, deterministic operations | Model: Large files, experiment tracking, safe loading

**For language-specific implementations:** See `python-3-development-standards.mdc` for Python-specific patterns.

---

*This file consolidates AI/ML-specific best practices for PyTorch, TensorFlow, and GPU-accelerated development. For universal anti-patterns, see `general-llm-anti-patterns.mdc`.*
