#include "RunnerArguments.h"

#include <string>
#include <string_view>

namespace dart_appkit {

std::string RunnerUsage(std::string_view executable) {
  return "Usage: " + std::string(executable) +
         " --kernel <file.dill> --sdk-version <version>"
         " --sdk-revision <revision> [-- application arguments...]\n";
}

bool ParseRunnerArguments(int argc, const char* const argv[],
                          RunnerConfiguration* configuration,
                          std::string* out_error) {
  if (configuration == nullptr || out_error == nullptr) {
    return false;
  }
  *configuration = RunnerConfiguration{};
  out_error->clear();
  if (argc < 1 || argv == nullptr || argv[0] == nullptr) {
    *out_error = "Runner argument vector is invalid";
    return false;
  }

  bool application_arguments = false;
  bool saw_kernel = false;
  bool saw_sdk_version = false;
  bool saw_sdk_revision = false;
  for (int index = 1; index < argc; ++index) {
    if (argv[index] == nullptr) {
      *out_error = "Runner argument vector contains a null value";
      return false;
    }
    const std::string_view argument(argv[index]);
    if (application_arguments) {
      configuration->application_arguments.emplace_back(argument);
      continue;
    }
    if (argument == "--") {
      application_arguments = true;
      continue;
    }

    auto read_value = [&](std::string* output, bool* seen) -> bool {
      if (*seen) {
        *out_error = std::string(argument) + " may be supplied only once";
        return false;
      }
      if (index + 1 >= argc || argv[index + 1] == nullptr) {
        *out_error = std::string(argument) + " requires a value";
        return false;
      }
      const std::string value(argv[++index]);
      if (value.empty()) {
        *out_error = std::string(argument) + " requires a non-empty value";
        return false;
      }
      *output = value;
      *seen = true;
      return true;
    };

    if (argument == "--kernel") {
      if (!read_value(&configuration->kernel_path, &saw_kernel)) {
        return false;
      }
    } else if (argument == "--sdk-version") {
      if (!read_value(&configuration->expected_sdk_version, &saw_sdk_version)) {
        return false;
      }
    } else if (argument == "--sdk-revision") {
      if (!read_value(&configuration->expected_sdk_revision,
                      &saw_sdk_revision)) {
        return false;
      }
    } else {
      *out_error = "unknown Runner argument: " + std::string(argument);
      return false;
    }
  }

  if (!saw_kernel) {
    *out_error = "--kernel is required";
    return false;
  }
  if (!saw_sdk_version) {
    *out_error = "--sdk-version is required";
    return false;
  }
  if (!saw_sdk_revision) {
    *out_error = "--sdk-revision is required";
    return false;
  }
  return true;
}

}  // namespace dart_appkit
