#include <cstdio>
#include <iterator>
#include <string>

#include "RunnerArguments.h"

namespace {

int g_failures = 0;

void Check(bool condition, const char* expression, int line) {
  if (!condition) {
    std::fprintf(stderr, "FAIL line %d: %s\n", line, expression);
    ++g_failures;
  }
}

#define CHECK(expression) Check((expression), #expression, __LINE__)

void TestValidArgumentsAndDelimiter() {
  const char* arguments[] = {
      "runner",        "--kernel", "/tmp/application.dill",
      "--sdk-version", "3.13.2",   "--sdk-revision",
      "revision",      "--",       "--application-flag",
      "two words",
  };
  dart_appkit::RunnerConfiguration configuration;
  std::string error;
  CHECK(
      dart_appkit::ParseRunnerArguments(static_cast<int>(std::size(arguments)),
                                        arguments, &configuration, &error));
  CHECK(error.empty());
  CHECK(configuration.kernel_path == "/tmp/application.dill");
  CHECK(configuration.expected_sdk_version == "3.13.2");
  CHECK(configuration.expected_sdk_revision == "revision");
  CHECK(configuration.application_arguments.size() == 2);
  CHECK(configuration.application_arguments[0] == "--application-flag");
  CHECK(configuration.application_arguments[1] == "two words");
}

void TestFailures() {
  dart_appkit::RunnerConfiguration configuration;
  std::string error;

  const char* missing[] = {"runner", "--kernel", "file"};
  CHECK(!dart_appkit::ParseRunnerArguments(static_cast<int>(std::size(missing)),
                                           missing, &configuration, &error));
  CHECK(error.find("--sdk-version is required") != std::string::npos);

  const char* no_value[] = {"runner", "--kernel"};
  CHECK(!dart_appkit::ParseRunnerArguments(
      static_cast<int>(std::size(no_value)), no_value, &configuration, &error));
  CHECK(error.find("requires a value") != std::string::npos);

  const char* duplicate[] = {
      "runner",        "--kernel", "one.dill",       "--kernel", "two.dill",
      "--sdk-version", "3.13.2",   "--sdk-revision", "revision",
  };
  CHECK(
      !dart_appkit::ParseRunnerArguments(static_cast<int>(std::size(duplicate)),
                                         duplicate, &configuration, &error));
  CHECK(error.find("only once") != std::string::npos);

  const char* unknown[] = {"runner", "--unknown"};
  CHECK(!dart_appkit::ParseRunnerArguments(static_cast<int>(std::size(unknown)),
                                           unknown, &configuration, &error));
  CHECK(error.find("unknown Runner argument") != std::string::npos);

  CHECK(!dart_appkit::ParseRunnerArguments(0, nullptr, &configuration, &error));
  CHECK(error.find("invalid") != std::string::npos);
}

void TestPublishedContract() {
  CHECK(dart_appkit::kRunnerUsageExitCode == 64);
  CHECK(dart_appkit::kRunnerInputExitCode == 66);
  CHECK(dart_appkit::kRunnerSoftwareExitCode == 70);
  CHECK(dart_appkit::RunnerUsage("runner").find("--sdk-revision") !=
        std::string::npos);
}

}  // namespace

int main() {
  TestValidArgumentsAndDelimiter();
  TestFailures();
  TestPublishedContract();
  if (g_failures != 0) {
    std::fprintf(stderr, "%d Runner argument test(s) failed\n", g_failures);
    return 1;
  }
  std::printf("all Runner argument tests passed\n");
  return 0;
}
