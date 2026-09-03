note
	description: "[
		THE FREEZE ASSAULT (1.0.1). The vector test for the defect Larry's
		simple_chat window found on 2026-09-02: the chat window stopped
		dead for 8 to 25 seconds at a time and Windows ghosted it and threw
		the keystrokes away.

		The mechanism was proved that day in simple_winhttp. It is a law of
		the runtime, not a fact about HTTP: ISE's garbage collector stops
		every thread of the system before it collects; a thread inside a
		plain `external "C inline"' call is where the runtime can neither
		see it nor stop it, so the collection WAITS for that call to return
		and every other processor waits with it, at its very next
		allocation.

		simple_process was the same shape, and worse. SIMPLE_PROCESS
		.execute runs a child process to completion - CreateProcess, a full
		drain of the child's stdout, and then
		`WaitForSingleObject(hProcess, INFINITE)'. There is no timeout on
		that wait at all. simple_chat's server runs `claude -p' through it,
		and a bot can think for two minutes: one question, and the whole
		chat server stopped for every user in it.

		Five tests, in the order the argument runs:

		1-3  THE LAW (BLOCKING_PROBE). The same wait, three ways: an Eiffel
		     sleep costs the root nothing; an UNMARKED C call costs it the
		     whole wait; the same call MARKED `blocking' costs it nothing
		     again. Test 2 asserts the freeze EXISTS - it is the mechanism,
		     and it passes before and after the fix. What changed in 1.0.1
		     is that this library no longer makes one.

		4    THE VECTOR, synchronous. A real SIMPLE_PROCESS.execute of a
		     three-second child on its own processor while the root does
		     nothing but allocate.

		5    THE VECTOR, asynchronous. The same child through
		     SIMPLE_ASYNC_PROCESS.start / .wait / .read_available_output -
		     three more externals that sit in the kernel.

		Before 1.0.1 the root's worst single allocation in 4 and 5 was in
		the thousands of milliseconds. After, it is single-digit. The
		budget is 500 ms - far under the roughly five seconds at which
		Windows ghosts a window, and far over the noise.

		Every OTHER wait in this assault is marked: EXECUTION_ENVIRONMENT
		.sleep is `C blocking' in ISE's own sources. The one unmarked wait
		is the one under test.
	]"
	author: "Larry Rix"

class
	SCOOP_TEST_APP

inherit
	PRECISE_CLOCK

create
	make

feature {NONE} -- Initialization

	make
			-- Run the assault.
		do
			print ("SIMPLE_PROCESS freeze assault (SCOOP): a waiting external must not stop the collector%N%N")
			passed := 0
			failed := 0

			run_test (agent test_an_eiffel_sleep_on_another_processor_never_stops_the_allocator,
				"an Eiffel sleep on another processor never stops the allocator")
			run_test (agent test_an_unmarked_c_call_on_another_processor_stops_the_allocator,
				"an unmarked C call on another processor stops the allocator")
			run_test (agent test_a_blocking_marked_c_call_never_stops_the_allocator,
				"a blocking-marked C call never stops the allocator")
			run_test (agent test_a_slow_child_process_never_stops_another_processors_allocator,
				"a slow SIMPLE_PROCESS execution never stops another processor's allocator")
			run_test (agent test_a_slow_async_wait_never_stops_another_processors_allocator,
				"a slow SIMPLE_ASYNC_PROCESS wait never stops another processor's allocator")

			print ("%N========================%N")
			print ("Results: " + passed.out + " passed, " + failed.out + " failed%N")
			if failed > 0 then
				print ("TESTS FAILED%N")
				(create {EXCEPTIONS}).die (1)
			else
				print ("ALL TESTS PASSED%N")
			end
		end

feature {NONE} -- Tests: the law

	test_an_eiffel_sleep_on_another_processor_never_stops_the_allocator
			-- EXECUTION_ENVIRONMENT.sleep is marked for the runtime, so a
			-- processor asleep in it never holds the collector.
		local
			l_probe: separate BLOCKING_PROBE
			l_worst: INTEGER_64
			l_done: INTEGER
		do
			create l_probe.make
			launch_eiffel_sleeps (l_probe)
			l_worst := worst_allocation_burst (Probe_bursts, Probe_gap_ms)
			l_done := waits_made (l_probe)
			print ("      an Eiffel sleep of " + (Probe_waits * Probe_wait_ms).out
				+ " ms on another processor: worst allocation on the root " + l_worst.out + " ms%N")
			assert ("the probe waited", l_done = Probe_waits)
			assert ("a marked wait leaves the root's allocator alone (" + l_worst.out + " ms)",
				l_worst <= Allocation_budget_ms)
		end

	test_an_unmarked_c_call_on_another_processor_stops_the_allocator
			-- THE MECHANISM. The same wait spent inside an unmarked external:
			-- the root's very next allocation waits for it.
		local
			l_probe: separate BLOCKING_PROBE
			l_worst: INTEGER_64
			l_done: INTEGER
		do
			create l_probe.make
			launch_unmarked_c_sleeps (l_probe)
			l_worst := worst_allocation_burst (Probe_bursts, Probe_gap_ms)
			l_done := waits_made (l_probe)
			print ("      an UNMARKED C call of " + Probe_wait_ms.out
				+ " ms on another processor: worst allocation on the root " + l_worst.out + " ms%N")
			assert ("the probe waited", l_done = Probe_waits)
			assert ("an unmarked wait stops the root's allocator for very nearly that long ("
				+ l_worst.out + " ms)", l_worst >= Probe_wait_ms // 2)
		end

	test_a_blocking_marked_c_call_never_stops_the_allocator
			-- THE FIX, in one keyword. The SAME Sleep, marked
			-- `external "C blocking inline"': the root allocates through it.
		local
			l_probe: separate BLOCKING_PROBE
			l_worst: INTEGER_64
			l_done: INTEGER
		do
			create l_probe.make
			launch_blocking_c_sleeps (l_probe)
			l_worst := worst_allocation_burst (Probe_bursts, Probe_gap_ms)
			l_done := waits_made (l_probe)
			print ("      a BLOCKING-marked C call of " + Probe_wait_ms.out
				+ " ms on another processor: worst allocation on the root " + l_worst.out + " ms%N")
			assert ("the probe waited", l_done = Probe_waits)
			assert ("the marker gives the collector the thread back (" + l_worst.out + " ms)",
				l_worst <= Allocation_budget_ms)
		end

feature {NONE} -- Tests: the vector

	test_a_slow_child_process_never_stops_another_processors_allocator
			-- THE RED-THEN-GREEN, synchronous. A real SIMPLE_PROCESS.execute
			-- of a three-second child on its own processor while the root
			-- does nothing but allocate.
			--
			-- Before 1.0.1 (`c_sp_execute_command' unmarked): worst
			-- allocation in the thousands of ms - simple_chat's freeze,
			-- reproduced in the library that caused it. After: single digits.
		local
			l_caller: separate PROCESS_CALLER
			l_worst, l_call_ms: INTEGER_64
			l_all: BOOLEAN
		do
			create l_caller.make
			launch_commands (l_caller, Executions)

			l_worst := worst_allocation_burst (Bursts, Burst_gap_ms)

			l_all := caller_ran_everything (l_caller, Executions)
			l_call_ms := caller_elapsed (l_caller)

			print ("      " + Executions.out + " x SIMPLE_PROCESS.execute of a "
				+ Child_life_ms.out + " ms child on another processor (" + l_call_ms.out
				+ " ms in the library): worst allocation on the root " + l_worst.out + " ms%N")
			assert ("every child ran to completion and printed", l_all)
			assert ("the children really were slow ones (" + l_call_ms.out + " ms for "
				+ Executions.out + " x " + Child_life_ms.out + " ms)",
				l_call_ms >= (Executions * Child_life_ms) * 8 // 10)
			assert ("no allocation on the root waited on the child (" + l_worst.out + " ms)",
				l_worst <= Allocation_budget_ms)
		end

	test_a_slow_async_wait_never_stops_another_processors_allocator
			-- THE RED-THEN-GREEN, asynchronous. The same child through
			-- SIMPLE_ASYNC_PROCESS: `c_sp_start_async', `c_sp_wait_timeout'
			-- and `c_sp_read_output'. A bounded wait is still a wait.
		local
			l_caller: separate PROCESS_CALLER
			l_worst, l_call_ms: INTEGER_64
			l_all: BOOLEAN
		do
			create l_caller.make
			launch_async_waits (l_caller, Executions)

			l_worst := worst_allocation_burst (Bursts, Burst_gap_ms)

			l_all := caller_ran_everything (l_caller, Executions)
			l_call_ms := caller_elapsed (l_caller)

			print ("      " + Executions.out + " x SIMPLE_ASYNC_PROCESS.wait on a "
				+ Child_life_ms.out + " ms child on another processor (" + l_call_ms.out
				+ " ms in the library): worst allocation on the root " + l_worst.out + " ms%N")
			assert ("every child ran to completion and printed", l_all)
			assert ("the waits really were slow ones (" + l_call_ms.out + " ms for "
				+ Executions.out + " x " + Child_life_ms.out + " ms)",
				l_call_ms >= (Executions * Child_life_ms) * 8 // 10)
			assert ("no allocation on the root waited on the child (" + l_worst.out + " ms)",
				l_worst <= Allocation_budget_ms)
		end

feature {NONE} -- The probe's processor (each a short, separate call)

	launch_eiffel_sleeps (a_probe: separate BLOCKING_PROBE)
			-- Start the marked sleeps; asynchronous.
		do
			a_probe.run_eiffel_sleeps (Probe_waits, Probe_wait_ms)
		end

	launch_unmarked_c_sleeps (a_probe: separate BLOCKING_PROBE)
			-- Start the unmarked C waits; asynchronous.
		do
			a_probe.run_unmarked_c_sleeps (Probe_waits, Probe_wait_ms)
		end

	launch_blocking_c_sleeps (a_probe: separate BLOCKING_PROBE)
			-- Start the marked C waits; asynchronous.
		do
			a_probe.run_blocking_c_sleeps (Probe_waits, Probe_wait_ms)
		end

	waits_made (a_probe: separate BLOCKING_PROBE): INTEGER
			-- How many waits the probe made. A query, so it joins the probe.
		do
			Result := a_probe.waits_done
		ensure
			non_negative: Result >= 0
		end

feature {NONE} -- The caller's processor (each a short, separate call)

	launch_commands (a_caller: separate PROCESS_CALLER; a_count: INTEGER)
			-- Start the synchronous executions; asynchronous, and only
			-- integers cross.
		require
			positive: a_count > 0
		do
			a_caller.run_commands (a_count)
		end

	launch_async_waits (a_caller: separate PROCESS_CALLER; a_count: INTEGER)
			-- Start the asynchronous runs; asynchronous.
		require
			positive: a_count > 0
		do
			a_caller.run_async_waits (a_count)
		end

	caller_ran_everything (a_caller: separate PROCESS_CALLER; a_count: INTEGER): BOOLEAN
			-- Did every child run and print? A query, so it joins the caller.
		require
			positive: a_count > 0
		do
			Result := a_caller.has_run_everything (a_count)
		end

	caller_elapsed (a_caller: separate PROCESS_CALLER): INTEGER_64
			-- How long the whole run took, in milliseconds.
		do
			Result := a_caller.elapsed_milliseconds
		ensure
			non_negative: Result >= 0
		end

feature {NONE} -- The root's own allocator

	worst_allocation_burst (a_bursts, a_gap_ms: INTEGER): INTEGER_64
			-- Allocate `a_bursts' times, `a_gap_ms' apart, and answer the
			-- longest single burst in milliseconds. Nothing here touches
			-- another processor: a burst that takes a second took it inside
			-- the runtime, waiting for a collection that cannot start.
		require
			positive: a_bursts > 0 and a_gap_ms > 0
		local
			l_env: EXECUTION_ENVIRONMENT
			l_live: ARRAYED_LIST [STRING_8]
			l_junk: ARRAYED_LIST [STRING_8]
			i, k: INTEGER
			t0, l_span: INTEGER_64
		do
			create l_env
			create l_live.make (a_bursts * Burst_kept)
			from
				i := 1
			until
				i > a_bursts
			loop
				t0 := now_ms
				create l_junk.make (Burst_strings)
				from
					k := 1
				until
					k > Burst_strings
				loop
					l_junk.extend (create {STRING_8}.make_filled ('x', Burst_string_bytes))
					if k <= Burst_kept then
							-- A live set that keeps growing, so the collector has
							-- something to mark and cannot answer every burst out
							-- of a free list it already owns.
						l_live.extend (l_junk.last)
					end
					k := k + 1
				variant
					Burst_strings + 1 - k
				end
				l_span := now_ms - t0
				if l_span > Result then
					Result := l_span
				end
				l_env.sleep (a_gap_ms.to_integer_64 * 1_000_000)
				i := i + 1
			variant
				a_bursts + 1 - i
			end
			check kept_them_alive: l_live.count = a_bursts * Burst_kept end
		ensure
			non_negative: Result >= 0
		end

feature {NONE} -- Test runner

	run_test (a_test: PROCEDURE; a_name: STRING_8)
			-- Run one test; any exception (contract or otherwise) fails it.
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_test.call (Void)
				print ("  PASS: " + a_name + "%N")
				passed := passed + 1
			end
		rescue
			print ("  FAIL: " + a_name + "%N")
			if attached (create {EXCEPTION_MANAGER}).last_exception as ex and then attached ex.description as d then
				print ("        " + d.to_string_8 + "%N")
			end
			failed := failed + 1
			l_retried := True
			retry
		end

	assert (a_tag: STRING_8; a_condition: BOOLEAN)
			-- Raise unless `a_condition', so `run_test' records the failure.
		do
			if not a_condition then
				print ("        FAILED: " + a_tag + "%N")
				(create {EXCEPTIONS}).raise ("freeze assault: " + a_tag)
			end
		end

	passed, failed: INTEGER

feature -- Constants: the probe

	Probe_waits: INTEGER = 1
			-- Waits the probe's processor makes.

	Probe_wait_ms: INTEGER = 3_000
			-- How long each of them lasts.

	Probe_bursts: INTEGER = 60

	Probe_gap_ms: INTEGER = 100
			-- 60 x 100 ms = 6 s, twice the probe's whole wait.

feature -- Constants: the vector

	Executions: INTEGER = 2
			-- Children the caller runs through the real library.

	Child_life_ms: INTEGER = 3_000
			-- How long each of them lives. Kept in step with
			-- {PROCESS_CALLER}.Child_life_ms.

	Bursts: INTEGER = 100

	Burst_gap_ms: INTEGER = 100
			-- 100 x 100 ms = 10 s, comfortably over the 6 s of children plus
			-- the interpreter startup each of them pays.

feature -- Constants: the bar

	Burst_strings: INTEGER = 2_000

	Burst_string_bytes: INTEGER = 1_024
			-- 2 MiB a burst: enough that the collector runs many times over.

	Burst_kept: INTEGER = 200
			-- 200 KiB of every burst is kept alive, so the heap grows and the
			-- collector has real work: an allocator that is never asked to
			-- collect can never be caught waiting for one.

	Allocation_budget_ms: INTEGER_64 = 500
			-- The bound, with margin. A frame is 16 ms; Windows ghosts a window
			-- that stops pumping for about five seconds. 500 ms is far under
			-- the harm and far over the noise - and the measured GREEN is
			-- single-digit, so nothing here is tuned to just barely pass.

invariant
	child_life_agrees: Child_life_ms = {PROCESS_CALLER}.Child_life_ms

end
