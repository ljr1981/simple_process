/*
 * simple_process.c - Win32 process execution wrapper for Eiffel
 *
 * Provides SCOOP-compatible process execution without thread dependencies.
 * Uses synchronous I/O for output capture.
 *
 * Copyright (c) 2025 Larry Rix - MIT License
 */

#include "simple_process.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BUFFER_SIZE 4096
#define MAX_OUTPUT_SIZE (1024 * 1024)  /* 1MB max output */

static char last_error_msg[512] = {0};

/* Store last error message */
static void store_last_error(void) {
    DWORD err = GetLastError();
    FormatMessageA(
        FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL,
        err,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        last_error_msg,
        sizeof(last_error_msg) - 1,
        NULL
    );
}

const char* sp_get_last_error(void) {
    return last_error_msg;
}

sp_result* sp_execute_command(const char* command, const char* working_dir, int show_window) {
    sp_result* result;
    SECURITY_ATTRIBUTES sa;
    HANDLE hStdOutRead = NULL, hStdOutWrite = NULL;
    HANDLE hStdErrRead = NULL, hStdErrWrite = NULL;
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    char* cmd_copy = NULL;
    char* output_buffer = NULL;
    int output_size = 0;
    int output_capacity = BUFFER_SIZE;
    DWORD bytes_read;
    char read_buffer[BUFFER_SIZE];
    BOOL success;

    /* Allocate result structure */
    result = (sp_result*)malloc(sizeof(sp_result));
    if (!result) return NULL;
    memset(result, 0, sizeof(sp_result));

    /* Set up security attributes for inheritable handles */
    sa.nLength = sizeof(SECURITY_ATTRIBUTES);
    sa.bInheritHandle = TRUE;
    sa.lpSecurityDescriptor = NULL;

    /* Create pipes for stdout */
    if (!CreatePipe(&hStdOutRead, &hStdOutWrite, &sa, 0)) {
        store_last_error();
        result->error_message = _strdup(last_error_msg);
        result->success = 0;
        return result;
    }

    /* Ensure read handle is not inherited */
    SetHandleInformation(hStdOutRead, HANDLE_FLAG_INHERIT, 0);

    /* Create pipes for stderr (redirect to stdout) */
    if (!DuplicateHandle(GetCurrentProcess(), hStdOutWrite,
                         GetCurrentProcess(), &hStdErrWrite,
                         0, TRUE, DUPLICATE_SAME_ACCESS)) {
        store_last_error();
        result->error_message = _strdup(last_error_msg);
        result->success = 0;
        CloseHandle(hStdOutRead);
        CloseHandle(hStdOutWrite);
        return result;
    }

    /* Set up startup info */
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    si.hStdOutput = hStdOutWrite;
    si.hStdError = hStdErrWrite;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.dwFlags |= STARTF_USESTDHANDLES;

    if (!show_window) {
        si.dwFlags |= STARTF_USESHOWWINDOW;
        si.wShowWindow = SW_HIDE;
    }

    /* CreateProcess needs a modifiable string */
    cmd_copy = _strdup(command);
    if (!cmd_copy) {
        result->error_message = _strdup("Memory allocation failed");
        result->success = 0;
        CloseHandle(hStdOutRead);
        CloseHandle(hStdOutWrite);
        CloseHandle(hStdErrWrite);
        return result;
    }

    memset(&pi, 0, sizeof(pi));

    /* Create the process */
    success = CreateProcessA(
        NULL,           /* Application name (use command line) */
        cmd_copy,       /* Command line */
        NULL,           /* Process security attributes */
        NULL,           /* Thread security attributes */
        TRUE,           /* Inherit handles */
        CREATE_NO_WINDOW, /* Creation flags */
        NULL,           /* Environment (inherit) */
        working_dir,    /* Working directory */
        &si,            /* Startup info */
        &pi             /* Process info */
    );

    free(cmd_copy);

    /* Close write ends of pipes (child has them now) */
    CloseHandle(hStdOutWrite);
    CloseHandle(hStdErrWrite);

    if (!success) {
        store_last_error();
        result->error_message = _strdup(last_error_msg);
        result->success = 0;
        CloseHandle(hStdOutRead);
        return result;
    }

    /* Allocate output buffer */
    output_buffer = (char*)malloc(output_capacity);
    if (!output_buffer) {
        result->error_message = _strdup("Memory allocation failed");
        result->success = 0;
        CloseHandle(hStdOutRead);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        return result;
    }

    /* Read output from pipe */
    while (1) {
        success = ReadFile(hStdOutRead, read_buffer, BUFFER_SIZE - 1, &bytes_read, NULL);
        if (!success || bytes_read == 0) break;

        /* Expand buffer if needed */
        if (output_size + bytes_read >= output_capacity) {
            int new_capacity = output_capacity * 2;
            char* new_buffer;
            if (new_capacity > MAX_OUTPUT_SIZE) {
                new_capacity = MAX_OUTPUT_SIZE;
            }
            if (output_size + bytes_read >= new_capacity) {
                break; /* Max size reached */
            }
            new_buffer = (char*)realloc(output_buffer, new_capacity);
            if (!new_buffer) break;
            output_buffer = new_buffer;
            output_capacity = new_capacity;
        }

        memcpy(output_buffer + output_size, read_buffer, bytes_read);
        output_size += bytes_read;
    }

    /* Null-terminate output */
    output_buffer[output_size] = '\0';

    CloseHandle(hStdOutRead);

    /* Wait for process to complete */
    WaitForSingleObject(pi.hProcess, INFINITE);

    /* Get exit code */
    GetExitCodeProcess(pi.hProcess, (DWORD*)&result->exit_code);

    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    result->success = 1;
    result->output = output_buffer;
    result->output_length = output_size;

    return result;
}

sp_result* sp_execute_with_args(const char* program, const char* args, const char* working_dir, int show_window) {
    char* full_command;
    sp_result* result;
    size_t len;

    if (args && args[0]) {
        len = strlen(program) + strlen(args) + 2;
        full_command = (char*)malloc(len);
        if (!full_command) {
            result = (sp_result*)malloc(sizeof(sp_result));
            if (result) {
                memset(result, 0, sizeof(sp_result));
                result->error_message = _strdup("Memory allocation failed");
            }
            return result;
        }
        sprintf(full_command, "%s %s", program, args);
    } else {
        full_command = _strdup(program);
    }

    result = sp_execute_command(full_command, working_dir, show_window);
    free(full_command);
    return result;
}

void sp_free_result(sp_result* result) {
    if (result) {
        if (result->output) free(result->output);
        if (result->error_message) free(result->error_message);
        free(result);
    }
}

int sp_file_in_path(const char* filename) {
    char path_buffer[MAX_PATH];
    DWORD result;

    result = SearchPathA(NULL, filename, ".exe", MAX_PATH, path_buffer, NULL);
    return (result > 0) ? 1 : 0;
}

/* ============ ASYNC PROCESS FUNCTIONS ============ */

sp_async_process* sp_start_async(const char* command, const char* working_dir, int show_window) {
    sp_async_process* proc;
    SECURITY_ATTRIBUTES sa;
    HANDLE hStdOutWrite = NULL;
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    char* cmd_copy = NULL;
    BOOL success;

    /* Allocate process structure */
    proc = (sp_async_process*)malloc(sizeof(sp_async_process));
    if (!proc) return NULL;
    memset(proc, 0, sizeof(sp_async_process));

    /* Set up security attributes for inheritable handles */
    sa.nLength = sizeof(SECURITY_ATTRIBUTES);
    sa.bInheritHandle = TRUE;
    sa.lpSecurityDescriptor = NULL;

    /* Create pipe for stdout */
    if (!CreatePipe(&proc->hStdOutRead, &hStdOutWrite, &sa, 0)) {
        store_last_error();
        proc->error_message = _strdup(last_error_msg);
        proc->started = 0;
        return proc;
    }

    /* Ensure read handle is not inherited */
    SetHandleInformation(proc->hStdOutRead, HANDLE_FLAG_INHERIT, 0);

    /* Set up startup info */
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    si.hStdOutput = hStdOutWrite;
    si.hStdError = hStdOutWrite;  /* Redirect stderr to stdout */
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.dwFlags |= STARTF_USESTDHANDLES;

    if (!show_window) {
        si.dwFlags |= STARTF_USESHOWWINDOW;
        si.wShowWindow = SW_HIDE;
    }

    /* CreateProcess needs a modifiable string */
    cmd_copy = _strdup(command);
    if (!cmd_copy) {
        proc->error_message = _strdup("Memory allocation failed");
        proc->started = 0;
        CloseHandle(proc->hStdOutRead);
        CloseHandle(hStdOutWrite);
        return proc;
    }

    memset(&pi, 0, sizeof(pi));

    /* Create the process */
    success = CreateProcessA(
        NULL,           /* Application name (use command line) */
        cmd_copy,       /* Command line */
        NULL,           /* Process security attributes */
        NULL,           /* Thread security attributes */
        TRUE,           /* Inherit handles */
        CREATE_NO_WINDOW, /* Creation flags */
        NULL,           /* Environment (inherit) */
        working_dir,    /* Working directory */
        &si,            /* Startup info */
        &pi             /* Process info */
    );

    free(cmd_copy);
    CloseHandle(hStdOutWrite);  /* Close write end - child has it */

    if (!success) {
        store_last_error();
        proc->error_message = _strdup(last_error_msg);
        proc->started = 0;
        CloseHandle(proc->hStdOutRead);
        return proc;
    }

    /* Store process info */
    proc->hProcess = pi.hProcess;
    proc->hThread = pi.hThread;
    proc->processId = pi.dwProcessId;
    proc->started = 1;

    return proc;
}

int sp_is_running(sp_async_process* proc) {
    DWORD exit_code;
    if (!proc || !proc->started || proc->hProcess == NULL) {
        return 0;
    }
    if (GetExitCodeProcess(proc->hProcess, &exit_code)) {
        return (exit_code == STILL_ACTIVE) ? 1 : 0;
    }
    return 0;
}

DWORD sp_get_pid(sp_async_process* proc) {
    if (!proc || !proc->started) return 0;
    return proc->processId;
}

int sp_wait_timeout(sp_async_process* proc, DWORD timeout_ms) {
    DWORD result;
    if (!proc || !proc->started || proc->hProcess == NULL) {
        return -1;
    }
    result = WaitForSingleObject(proc->hProcess, timeout_ms);
    if (result == WAIT_OBJECT_0) {
        return 1;  /* Process finished */
    } else if (result == WAIT_TIMEOUT) {
        return 0;  /* Timeout */
    }
    return -1;  /* Error */
}

int sp_kill(sp_async_process* proc) {
    if (!proc || !proc->started || proc->hProcess == NULL) {
        return 0;
    }
    if (TerminateProcess(proc->hProcess, 1)) {
        return 1;
    }
    return 0;
}

int sp_get_exit_code(sp_async_process* proc) {
    DWORD exit_code;
    if (!proc || !proc->started || proc->hProcess == NULL) {
        return -1;
    }
    if (GetExitCodeProcess(proc->hProcess, &exit_code)) {
        if (exit_code == STILL_ACTIVE) {
            return -1;  /* Still running */
        }
        return (int)exit_code;
    }
    return -1;
}

char* sp_read_output(sp_async_process* proc, int* out_length) {
    char* buffer = NULL;
    char read_buffer[4096];
    DWORD bytes_available, bytes_read;
    int total_size = 0;
    int buffer_capacity = 0;

    *out_length = 0;

    if (!proc || !proc->started || proc->hStdOutRead == NULL) {
        return NULL;
    }

    /* Check if data is available (non-blocking) */
    if (!PeekNamedPipe(proc->hStdOutRead, NULL, 0, NULL, &bytes_available, NULL)) {
        return NULL;
    }

    if (bytes_available == 0) {
        return NULL;  /* No data available */
    }

    /* Allocate initial buffer */
    buffer_capacity = (bytes_available > 4096) ? bytes_available + 1 : 4096;
    buffer = (char*)malloc(buffer_capacity);
    if (!buffer) return NULL;

    /* Read available data */
    while (PeekNamedPipe(proc->hStdOutRead, NULL, 0, NULL, &bytes_available, NULL) && bytes_available > 0) {
        DWORD to_read = (bytes_available > sizeof(read_buffer) - 1) ? sizeof(read_buffer) - 1 : bytes_available;

        if (ReadFile(proc->hStdOutRead, read_buffer, to_read, &bytes_read, NULL) && bytes_read > 0) {
            /* Expand buffer if needed */
            if (total_size + bytes_read >= buffer_capacity) {
                int new_capacity = buffer_capacity * 2;
                char* new_buffer = (char*)realloc(buffer, new_capacity);
                if (!new_buffer) break;
                buffer = new_buffer;
                buffer_capacity = new_capacity;
            }
            memcpy(buffer + total_size, read_buffer, bytes_read);
            total_size += bytes_read;
        } else {
            break;
        }
    }

    buffer[total_size] = '\0';
    *out_length = total_size;
    return buffer;
}

void sp_async_close(sp_async_process* proc) {
    if (proc) {
        if (proc->hProcess) CloseHandle(proc->hProcess);
        if (proc->hThread) CloseHandle(proc->hThread);
        if (proc->hStdOutRead) CloseHandle(proc->hStdOutRead);
        if (proc->error_message) free(proc->error_message);
        free(proc);
    }
}
