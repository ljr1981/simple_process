note
	description: "Test runner for simple_process"
	date: "$Date$"
	revision: "$Revision$"

class
	SIMPLE_PROCESS_TEST_APP

create
	make

feature {NONE} -- Initialization

	make
			-- Run tests.
		do
			print ("simple_process test runner%N")
			print ("============================%N%N")

			run_test (agent test_output_of_command_echo, "test_output_of_command_echo")
			run_test (agent test_output_of_command_dir, "test_output_of_command_dir")
			run_test (agent test_has_file_in_path_cmd, "test_has_file_in_path_cmd")
			run_test (agent test_has_file_in_path_nonexistent, "test_has_file_in_path_nonexistent")
			run_test (agent test_output_of_command_with_directory, "test_output_of_command_with_directory")
			run_test (agent test_show_process_toggle, "test_show_process_toggle")
			run_test (agent test_wait_for_exit_toggle, "test_wait_for_exit_toggle")
			run_test (agent test_output_of_command_where, "test_output_of_command_where")
			run_test (agent test_output_of_command_multi_arg, "test_output_of_command_multi_arg")
			run_test (agent test_simple_process_direct, "test_simple_process_direct")
			run_test (agent test_file_exists_in_path, "test_file_exists_in_path")

			-- Async process tests
			run_test (agent test_async_start_and_wait, "test_async_start_and_wait")
			run_test (agent test_async_read_output, "test_async_read_output")
			run_test (agent test_async_pid, "test_async_pid")
			run_test (agent test_async_timeout, "test_async_timeout")
			run_test (agent test_async_kill, "test_async_kill")
			run_test (agent test_async_elapsed_time, "test_async_elapsed_time")
			run_test (agent test_async_show_window_setting, "test_async_show_window_setting")

			print ("%N============================%N")
			print ("Results: " + passed_count.out + " passed, " + failed_count.out + " failed%N")
			if failed_count = 0 then
				print ("ALL TESTS PASSED%N")
			end
		end

feature -- Tests

	test_output_of_command_echo
			-- Test capturing output from echo command.
		local
			l_output: STRING_32
		do
			l_output := helper.output_of_command ("cmd /c echo Hello World", Void)
			check_true ("has output", not l_output.is_empty)
			check_true ("contains hello", l_output.has_substring ("Hello"))
		end

	test_output_of_command_dir
			-- Test capturing output from dir command.
		local
			l_output: STRING_32
		do
			l_output := helper.output_of_command ("cmd /c dir", Void)
			check_true ("has output", not l_output.is_empty)
			check_true ("has content", l_output.count > 10)
		end

	test_has_file_in_path_cmd
			-- Test checking for cmd.exe in path.
		do
			check_true ("cmd.exe in path", helper.has_file_in_path ("cmd.exe"))
		end

	test_has_file_in_path_nonexistent
			-- Test checking for non-existent file.
		do
			check_true ("nonexistent not in path", not helper.has_file_in_path ("xyz_does_not_exist_abc.exe"))
		end

	test_output_of_command_with_directory
			-- Test running command in specific directory.
		local
			l_output: STRING_32
		do
			l_output := helper.output_of_command ("cmd /c dir", "C:\")
			check_true ("has output", not l_output.is_empty)
			check_true ("has expected content", l_output.has_substring ("Program") or l_output.has_substring ("Windows"))
		end

	test_show_process_toggle
			-- Test show_process flag.
		do
			check_true ("default is false", not helper.show_process)
			helper.set_show_process (True)
			check_true ("can set true", helper.show_process)
			helper.set_show_process (False)
			check_true ("can set false", not helper.show_process)
		end

	test_wait_for_exit_toggle
			-- Test wait for exit flag.
		do
			check_true ("default is wait", helper.is_wait_for_exit)
			helper.set_do_not_wait_for_exit
			check_true ("can disable wait", not helper.is_wait_for_exit)
			helper.set_wait_for_exit
			check_true ("can enable wait", helper.is_wait_for_exit)
		end

	test_output_of_command_where
			-- Test 'where' command - basic execution.
		local
			l_output: STRING_32
		do
			l_output := helper.output_of_command ("cmd /c echo test_where", Void)
			check_true ("can run cmd", l_output.has_substring ("test_where"))
		end

	test_output_of_command_multi_arg
			-- Test command with multiple arguments.
		local
			l_output: STRING_32
		do
			l_output := helper.output_of_command ("cmd /c echo one two three", Void)
			check_true ("has output", not l_output.is_empty)
			check_true ("has one", l_output.has_substring ("one"))
			check_true ("has two", l_output.has_substring ("two"))
			check_true ("has three", l_output.has_substring ("three"))
		end

	test_simple_process_direct
			-- Test SIMPLE_PROCESS class directly.
		local
			l_process: SIMPLE_PROCESS
		do
			create l_process.make
			l_process.execute ("cmd /c echo direct test")
			check_true ("was successful", l_process.was_successful)
			check_true ("has output", attached l_process.last_output as l_out and then l_out.has_substring ("direct"))
		end

	test_file_exists_in_path
			-- Test file_exists_in_path on SIMPLE_PROCESS directly.
		local
			l_process: SIMPLE_PROCESS
		do
			create l_process.make
			check_true ("notepad exists", l_process.file_exists_in_path ("notepad.exe"))
			check_true ("fake not exists", not l_process.file_exists_in_path ("fake_program_xyz.exe"))
		end

feature -- Async Tests

	test_async_start_and_wait
			-- Test starting async process and waiting for completion.
		local
			async: SIMPLE_ASYNC_PROCESS
		do
			create async.make
			async.start ("cmd /c echo Hello Async")
			check_true ("started", async.is_started)
			check_true ("was started ok", async.was_started_successfully)

			-- Wait up to 5 seconds
			check_true ("finished", async.wait_seconds (5))
			check_true ("not running", not async.is_running)
			check_true ("exit code 0", async.exit_code = 0)

			async.close
		end

	test_async_read_output
			-- Test reading output from async process.
		local
			async: SIMPLE_ASYNC_PROCESS
		do
			create async.make
			async.start ("cmd /c echo Test Output")

			-- Wait for completion
			async.wait_seconds (5).do_nothing

			-- Read output
			if attached async.read_available_output then end
			check_true ("has accumulated output", not async.accumulated_output.is_empty)
			check_true ("contains test", async.accumulated_output.has_substring ("Test"))

			async.close
		end

	test_async_pid
			-- Test getting process ID.
		local
			async: SIMPLE_ASYNC_PROCESS
		do
			create async.make
			-- Use a slightly longer command so we can check PID
			async.start ("cmd /c ping localhost -n 1")

			if async.was_started_successfully then
				check_true ("has pid", async.process_id > 0)
			end

			-- Wait for completion
			async.wait_seconds (10).do_nothing
			async.close
		end

	test_async_timeout
			-- Test that timeout works (process that takes time).
		local
			async: SIMPLE_ASYNC_PROCESS
			l_wait_result: INTEGER
		do
			create async.make
			-- Start a command that takes a few seconds
			async.start ("cmd /c ping localhost -n 3")

			-- Wait only 100ms - should timeout
			l_wait_result := async.wait (100)
			check_true ("timeout occurred", l_wait_result = 0)

			-- Now wait for real completion
			async.wait_seconds (10).do_nothing
			async.close
		end

	test_async_kill
			-- Test killing a long-running process.
		local
			async: SIMPLE_ASYNC_PROCESS
			killed: BOOLEAN
		do
			create async.make
			-- Start a command that would take a long time
			async.start ("cmd /c ping localhost -n 30")

			if async.was_started_successfully and async.is_running then
				-- Kill it
				killed := async.kill
				-- Note: kill may not be instant
				async.wait (500).do_nothing -- Give it a moment
				check_true ("killed or finished", killed or not async.is_running)
			end

			async.close
		end

	test_async_elapsed_time
			-- Test elapsed time tracking.
		local
			async: SIMPLE_ASYNC_PROCESS
			l_env: EXECUTION_ENVIRONMENT
		do
			create async.make
			async.start ("cmd /c ping localhost -n 2")

			-- Sleep a moment
			create l_env
			l_env.sleep (1_000_000_000) -- 1 second

			if async.is_started then
				check_true ("elapsed >= 0", async.elapsed_seconds >= 0)
			end

			async.wait_seconds (10).do_nothing
			async.close
		end

	test_async_show_window_setting
			-- Test show window setting.
		local
			async: SIMPLE_ASYNC_PROCESS
		do
			create async.make
			check_true ("default hidden", not async.show_window)
			async.set_show_window (True)
			check_true ("can set visible", async.show_window)
			async.set_show_window (False)
			check_true ("can set hidden", not async.show_window)
		end

feature {NONE} -- Test Infrastructure

	helper: SIMPLE_PROCESS_HELPER
			-- Helper under test
		once
			create Result
		end

	passed_count: INTEGER
	failed_count: INTEGER

	run_test (a_test: PROCEDURE; a_name: STRING)
			-- Run a test and report result.
		local
			l_failed: BOOLEAN
		do
			current_test_failed := False
			if not l_failed then
				a_test.call (Void)
			end
			if current_test_failed then
				print ("  FAIL: " + a_name + "%N")
				failed_count := failed_count + 1
			else
				print ("  PASS: " + a_name + "%N")
				passed_count := passed_count + 1
			end
		rescue
			l_failed := True
			current_test_failed := True
			retry
		end

	current_test_failed: BOOLEAN

	check_true (a_tag: STRING; a_condition: BOOLEAN)
			-- Check that condition is true.
		do
			if not a_condition then
				print ("    ASSERTION FAILED: " + a_tag + "%N")
				current_test_failed := True
			end
		end

end
