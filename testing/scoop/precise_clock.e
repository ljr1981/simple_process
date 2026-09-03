note
	description: "[
		Milliseconds off the machine's high-resolution counter, for
		measuring a stall that a one-second clock would round away.

		`now_ms' is itself an unmarked external, deliberately: it takes
		a fraction of a microsecond, so it can never be the thing the
		assault measures.
	]"
	author: "Larry Rix"

class
	PRECISE_CLOCK

feature -- Access

	now_ms: INTEGER_64
			-- Milliseconds off QueryPerformanceCounter.
		external
			"C inline use <windows.h>"
		alias
			"LARGE_INTEGER c, f; QueryPerformanceCounter(&c); QueryPerformanceFrequency(&f); return (EIF_INTEGER_64) ((c.QuadPart * 1000) / f.QuadPart);"
		end

end
