/**
 * Canary - A free and open-source MMORPG server emulator
 * Copyright (©) 2019–present OpenTibiaBR <opentibiabr@outlook.com>
 * Repository: https://github.com/opentibiabr/canary
 * License: https://github.com/opentibiabr/canary/blob/main/LICENSE
 * Contributors: https://github.com/opentibiabr/canary/graphs/contributors
 * Website: https://docs.opentibiabr.com/
 */

#include "canary_server.hpp"
#include "lib/di/container.hpp"

#ifndef USE_PRECOMPILED_HEADERS
	#include <span>
	#include <string_view>
#endif

#if defined(_WIN32) && defined(_MSC_VER)
	#ifndef NOMINMAX
		#define NOMINMAX
	#endif
	#include <windows.h>
	#include <dbghelp.h>
	#include <cstdio>
	#include <ctime>
	#pragma comment(lib, "dbghelp.lib")

namespace {
	// Writes the faulting thread's call stack to crash_stack.log (symbolized with canary.pdb) when the
	// process dies from an unhandled exception, so Windows crashes can be diagnosed without a debugger.
	LONG WINAPI writeCrashStack(EXCEPTION_POINTERS* exceptionInfo) {
		FILE* file = nullptr;
		if (fopen_s(&file, "crash_stack.log", "a") != 0 || !file) {
			return EXCEPTION_CONTINUE_SEARCH;
		}

		const auto now = std::time(nullptr);
		std::tm localTm {};
		localtime_s(&localTm, &now);
		char timeText[32] {};
		std::strftime(timeText, sizeof(timeText), "%Y-%m-%d %H:%M:%S", &localTm);

		const auto* record = exceptionInfo->ExceptionRecord;
		std::fprintf(file, "==== Crash %s  code=0x%08lX  thread=%lu\n", timeText, record->ExceptionCode, GetCurrentThreadId());
		if (record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION && record->NumberParameters >= 2) {
			std::fprintf(file, "access violation %s address 0x%llX\n", record->ExceptionInformation[0] == 0 ? "reading" : "writing", static_cast<unsigned long long>(record->ExceptionInformation[1]));
		}

		const HANDLE process = GetCurrentProcess();
		const HANDLE thread = GetCurrentThread();
		SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES);
		SymInitialize(process, nullptr, TRUE);

		CONTEXT context = *exceptionInfo->ContextRecord;
		STACKFRAME64 frame {};
		frame.AddrPC.Offset = context.Rip;
		frame.AddrPC.Mode = AddrModeFlat;
		frame.AddrFrame.Offset = context.Rbp;
		frame.AddrFrame.Mode = AddrModeFlat;
		frame.AddrStack.Offset = context.Rsp;
		frame.AddrStack.Mode = AddrModeFlat;

		const auto moduleBase = reinterpret_cast<DWORD64>(GetModuleHandleW(nullptr));
		alignas(SYMBOL_INFO) char symbolBuffer[sizeof(SYMBOL_INFO) + MAX_SYM_NAME] {};
		auto* symbol = reinterpret_cast<SYMBOL_INFO*>(symbolBuffer);

		for (int depth = 0; depth < 64; ++depth) {
			if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, thread, &frame, &context, nullptr, SymFunctionTableAccess64, SymGetModuleBase64, nullptr) || frame.AddrPC.Offset == 0) {
				break;
			}

			const DWORD64 address = frame.AddrPC.Offset;
			symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
			symbol->MaxNameLen = MAX_SYM_NAME;
			DWORD64 symbolOffset = 0;
			const char* name = SymFromAddr(process, address, &symbolOffset, symbol) ? symbol->Name : "?";

			IMAGEHLP_LINE64 line {};
			line.SizeOfStruct = sizeof(line);
			DWORD lineOffset = 0;
			if (SymGetLineFromAddr64(process, address, &lineOffset, &line)) {
				std::fprintf(file, "#%02d rva=0x%llX %s  %s:%lu\n", depth, static_cast<unsigned long long>(address - moduleBase), name, line.FileName, line.LineNumber);
			} else {
				std::fprintf(file, "#%02d rva=0x%llX %s\n", depth, static_cast<unsigned long long>(address - moduleBase), name);
			}
		}

		std::fprintf(file, "\n");
		std::fclose(file);
		SymCleanup(process);
		return EXCEPTION_CONTINUE_SEARCH;
	}
}
#endif

namespace {
	constexpr std::string_view GenerateLuaApiDocsOnlyArgument = "--generate-lua-api-docs-only";

	bool hasArgument(const std::span<char*> arguments, const std::string_view expectedArgument) {
		for (std::size_t index = 1; index < arguments.size(); ++index) {
			if (std::string_view(arguments[index]) == expectedArgument) {
				return true;
			}
		}
		return false;
	}
}

int main(int argc, char* argv[]) {
#if defined(_WIN32) && defined(_MSC_VER)
	SetUnhandledExceptionFilter(writeCrashStack);
#endif
	auto &server = inject<CanaryServer>();
	const std::span<char*> arguments(argv, static_cast<std::size_t>(argc));
	if (hasArgument(arguments, GenerateLuaApiDocsOnlyArgument)) {
		return server.generateLuaApiDocsOnly();
	}

	return server.run();
}
