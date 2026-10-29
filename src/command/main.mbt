///|
#cfg(target="native")
extern "C" fn exit_process(code : Int32) -> Unit = "exit"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn exit_process(code : Int32) -> Unit = "moonbitlang/async" "runtime/exit"

///|
async fn execute() -> Unit {
  let args = @env.args()
  if args.length() == 2 && ["help", "--help"].contains(args[1]) {
    @stdio.stdout.write(
      "FontPin: freeze all axes of a supported variable TrueType font\n\ninspect FILE\ninstance INPUT.ttf OUTPUT.ttf [axis=value ...]\n\nOmitted axes use defaults. OUTPUT must not exist. Diagnostics go to stderr.\n",
    )
    return
  }
  if args.length() == 3 && args[1] == "inspect" {
    @stdio.stdout.write(
      @fontpin.inspect_font(read_font(args[2])).stringify() + "\n",
    )
    return
  }
  if args.length() < 4 || args[1] != "instance" {
    fail("usage: inspect FILE | instance INPUT OUTPUT [axis=value ...]")
  }
  let coordinates : Map[String, Double] = Map([])
  for arg in args[4:] {
    let parts = arg.split("=").to_array()
    if parts.length() != 2 || parts[0].length() != 4 {
      fail("axis coordinate must have four-character tag=value form: " + arg)
    }
    let tag = parts[0].to_owned()
    if coordinates.contains(tag) {
      fail("duplicate axis: " + tag)
    }
    let value = @string.parse_double(parts[1]) catch {
      _ => fail("invalid numeric coordinate: " + arg)
    }
    coordinates[tag] = value
  }
  let font = @fontpin.Font::parse(read_font(args[2]))
  let instance = font.instantiate(coordinates)
  publish_font(args[3], instance.to_bytes())
  @stdio.stdout.write(instance.report_json().stringify() + "\n")
}

///|
async fn main {
  execute() catch {
    @fontpin.Invalid(detail) => {
      @stdio.stderr.write("invalid font: " + detail + "\n")
      exit_process(1)
    }
    @fontpin.Unsupported(detail) => {
      @stdio.stderr.write("unsupported font: " + detail + "\n")
      exit_process(1)
    }
    @fontpin.Limit(detail) => {
      @stdio.stderr.write("resource limit: " + detail + "\n")
      exit_process(1)
    }
    error => {
      @stdio.stderr.write("fontpin: " + error.to_string() + "\n")
      exit_process(1)
    }
  }
}
