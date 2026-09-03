# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Testing config updates, AutoTest fixes, .gitignore cleanup
- Migrate to simple_testing library
- Add SCOOP-compatible C wrapper (no more Eiffel process dependency)
- Add GitHub Pages documentation
- Update ref docs paths in roadmap
- Add documentation and .gitignore
- init
- first commit

## [1.0.1] - 2026-09-02

### Fixed
- **Every external that waits on a child process is now marked `blocking`.**
  `SIMPLE_PROCESS.c_sp_execute_command` - the one call that runs a whole child
  process - was declared `external "C inline use "simple_process.h""` with no
  `blocking` marker. ISE's garbage collector stops every thread of the system
  before it collects, and a thread inside an unmarked external is where the
  runtime can neither see it nor stop it: the collection waits for that call to
  return, and every other processor waits with it, at its very next allocation.
  A library whose whole purpose is to wait for a child therefore stopped the
  entire program for the length of every command.

  It was the worst case of the shape. `sp_execute_command` does CreateProcess,
  a full drain of the child's stdout pipe, and then
  `WaitForSingleObject(pi.hProcess, INFINITE)`. There is no timeout on that
  wait at all. simple_chat's server runs `claude -p` through it and a bot can
  think for two minutes: one question, and the chat server froze for every user
  in it.

  Five externals are now marked:

  | External | What it waits on |
  |---|---|
  | `SIMPLE_PROCESS.c_sp_execute_command` | a child's whole life - `WaitForSingleObject(..., INFINITE)` |
  | `SIMPLE_PROCESS.c_sp_file_in_path` | `SearchPathA` over every PATH entry (POSIX: `system ("command -v ...")`) |
  | `SIMPLE_ASYNC_PROCESS.c_sp_start_async` | CreateProcess - image load, and any AV filter driver in front of it |
  | `SIMPLE_ASYNC_PROCESS.c_sp_wait_timeout` | `WaitForSingleObject(..., timeout)` - bounded is not short |
  | `SIMPLE_ASYNC_PROCESS.c_sp_read_output` | a `PeekNamedPipe`-guarded `ReadFile` loop |

  It is safe to mark all five because nothing the C layer touches is
  Eiffel-collected memory. Every string crossing the boundary is a `C_STRING`,
  whose buffer `MANAGED_POINTER.make` allocates with `memory_calloc` on the C
  heap; the process handles are malloc'd structures this library owns; results
  are malloc'd and read only after the call returns. The one out parameter,
  `c_sp_read_output`'s `$a_len`, is the address of a LOCAL `INTEGER` of its sole
  caller `read_available_output` - it lives in that routine's own C stack frame,
  never in an object the collector may move.

  Deliberately left unmarked: the struct-field readers (`c_sp_result_success`,
  `c_sp_result_exit_code`, `c_sp_result_output`, `c_sp_result_output_length`,
  `c_sp_result_error`, `c_sp_async_started`, `c_sp_async_error`,
  `c_sp_get_pid`), the handle calls that cannot wait (`c_sp_is_running` and
  `c_sp_get_exit_code`, one `GetExitCodeProcess`; `c_sp_kill`, one asynchronous
  `TerminateProcess`; `c_sp_async_close`, three `CloseHandle`s and a `free`),
  and the two deallocators (`c_sp_free_result`, `c_free`). Each is a
  microsecond of bookkeeping, and a marker costs a runtime transition on every
  call.

  HOW IT WAS FOUND. Larry's simple_chat window froze on 2026-09-02 - 13 stalls
  and 211 seconds of frozen window in one 20-minute session. That hunt ended in
  simple_winhttp (see its CHANGELOG 0.1.1) and proved the mechanism; this
  library was audited against the same law the same day and was found carrying
  five of them, including an unbounded one.

  MEASURED, on the same machine, same duration, nothing else running: a
  processor asleep 3,000 ms in `EXECUTION_ENVIRONMENT.sleep` (which EiffelBase
  itself marks `C blocking`) cost another processor's worst allocation 3 ms; a
  processor inside a 3,000 ms UNMARKED C call cost it 2,896 ms.

### Added
- `simple_process_scoop_tests` - a SCOOP test target carrying the vector test
  that would have caught this. `PROCESS_CALLER` drives the real
  `SIMPLE_PROCESS` and `SIMPLE_ASYNC_PROCESS` from its own processor against a
  real child that lives three seconds; the root does nothing but allocate, with
  a live set that keeps growing so the collector always has work, and records
  its worst single allocation. `BLOCKING_PROBE` holds the law itself - the same
  wait taken three ways (an Eiffel sleep, an unmarked C call, the same C call
  marked `blocking`).

  RED (unmarked): the root's worst allocation was **3,166 ms** against
  `SIMPLE_PROCESS.execute` and **3,053 ms** against `SIMPLE_ASYNC_PROCESS.wait`.
  3 passed, 2 failed.
  GREEN (1.0.1): **4 ms** and **4 ms**, with the children still taking their
  full 6,356 ms and 6,371 ms in the library. 5 passed, 0 failed. The assertion
  is bounded at 500 ms, with margin on both sides.

  The existing suite is 17 passed / 0 failed either way.

### Changed
- `SIMPLE_PROCESS` and `SIMPLE_ASYNC_PROCESS` class notes and the README now
  state the guarantee: a child process running here never stops another
  processor's allocator.
- `package.json` version corrected to match the CHANGELOG (it had been left at
  `0.1.0` while the CHANGELOG and README released `1.0.0`).

[1.0.1]: https://github.com/simple-eiffel/simple_process/releases/tag/v1.0.1

## [1.0.0] - 2025-12-08

### Added
- Initial release
- Core functionality implemented
- Test suite with comprehensive coverage
- Documentation and examples

[Unreleased]: https://github.com/simple-eiffel/simple_process/compare/v1.0.1...HEAD
[1.0.0]: https://github.com/simple-eiffel/simple_process/releases/tag/v1.0.0
