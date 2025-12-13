note
	description: "Test application for SIMPLE_PROCESS"
	author: "Larry Rix"

class
	TEST_APP

create
	make

feature {NONE} -- Initialization

	make
			-- Run the tests.
		do
			print ("Running SIMPLE_PROCESS tests...%N%N")
			passed := 0
			failed := 0

			run_lib_tests
			run_simple_process_tests

			print ("%N========================%N")
			print ("Results: " + passed.out + " passed, " + failed.out + " failed%N")

			if failed > 0 then
				print ("TESTS FAILED%N")
			else
				print ("ALL TESTS PASSED%N")
			end
		end

feature {NONE} -- Test Runners

	run_lib_tests
		do
			create lib_tests
			run_test (agent lib_tests.test_output_of_command, "test_output_of_command")
			run_test (agent lib_tests.test_has_file_in_path, "test_has_file_in_path")
			run_test (agent lib_tests.test_show_process_flag, "test_show_process_flag")
			run_test (agent lib_tests.test_wait_for_exit_flag, "test_wait_for_exit_flag")
			run_test (agent lib_tests.test_simple_process_make, "test_simple_process_make")
			run_test (agent lib_tests.test_simple_process_show_window, "test_simple_process_show_window")
			run_test (agent lib_tests.test_async_process_make, "test_async_process_make")
			run_test (agent lib_tests.test_output_with_directory, "test_output_with_directory")
		end

	run_simple_process_tests
		do
			create process_tests
			run_test (agent process_tests.test_output_of_command_echo, "test_output_of_command_echo")
			run_test (agent process_tests.test_output_of_command_dir, "test_output_of_command_dir")
			run_test (agent process_tests.test_has_file_in_path_cmd, "test_has_file_in_path_cmd")
			run_test (agent process_tests.test_has_file_in_path_nonexistent, "test_has_file_in_path_nonexistent")
			run_test (agent process_tests.test_output_of_command_with_directory, "test_output_of_command_with_directory")
			run_test (agent process_tests.test_show_process_toggle, "test_show_process_toggle")
			run_test (agent process_tests.test_wait_for_exit_toggle, "test_wait_for_exit_toggle")
			run_test (agent process_tests.test_output_of_command_where, "test_output_of_command_where")
			run_test (agent process_tests.test_output_of_command_multi_arg, "test_output_of_command_multi_arg")
		end

feature {NONE} -- Implementation

	lib_tests: LIB_TESTS
	process_tests: TEST_SIMPLE_PROCESS

	passed: INTEGER
	failed: INTEGER

	run_test (a_test: PROCEDURE; a_name: STRING)
			-- Run a single test and update counters.
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
			failed := failed + 1
			l_retried := True
			retry
		end

end
