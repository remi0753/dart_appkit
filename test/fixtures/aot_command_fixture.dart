@pragma('vm:entry-point')
void main(List<String> arguments) {
  print('AOT_COMMAND_PASS ${arguments.join(',')}');
}
