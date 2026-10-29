// SPDX-License-Identifier: Apache-2.0
// Directory publication adapts the file-publication pattern in files.mbt.
// See THIRD_PARTY.md and LICENSES/Apache-2.0.txt.

///|
async fn publish_batch(
  destination : String,
  artifacts : Array[@fontpin.BatchArtifact],
  report : Json,
) -> Unit {
  guard @env.rand(16) is Some(random) else {
    fail("batch temporary name unavailable")
  }
  let digits = "0123456789abcdef".to_array()
  let suffix = StringBuilder()
  for byte in random {
    suffix.write_char(digits[byte.to_int() >> 4])
    suffix.write_char(digits[byte.to_int() & 15])
  }
  let staging = destination + "." + suffix.to_string() + ".pending"
  @async.protect_from_cancel(() => {
    @fs.mkdir(staging[:])
    let written : Array[String] = []
    let mut published = false
    defer (if !published {
      // Remove only files this operation created; never recursively delete a
      // path that could contain unrelated concurrent filesystem changes.
      for filename in written {
        @fs.remove((staging + "/" + filename)[:]) catch {
          _ =>
            @stdio.stderr.write(
              "cleanup failed: remove " + staging + "/" + filename + "\n",
            )
        }
      }
      @fs.rmdir(staging[:]) catch {
        _ =>
          @stdio.stderr.write(
            "cleanup failed: remove directory " + staging + "\n",
          )
      }
    })
    for artifact in artifacts {
      let file = @fs.create(
        (staging + "/" + artifact.filename)[:],
        allow_existing=false,
        permission=0o644,
      )
      written.push(artifact.filename)
      defer file.close()
      file.write(artifact.instance.to_bytes())
      file.sync()
    }
    {
      let file = @fs.create(
        (staging + "/manifest.json")[:],
        allow_existing=false,
        permission=0o644,
      )
      written.push("manifest.json")
      defer file.close()
      file.write(report.stringify() + "\n")
      file.sync()
    }
    // Sibling staging guarantees a same-filesystem, no-replace rename.
    // Visibility is all-or-nothing; power-loss durability is not promised.
    @fs.rename(staging[:], destination[:], replace=false)
    published = true
  })
}

///|
async fn execute_batch(
  source : String,
  destination : String,
  manifest : String,
) -> Unit {
  let segments = destination
    .replace_all(old="\\", new="/")
    .split("/")
    .to_array()
  let leaf = segments[segments.length() - 1].to_owned()
  if leaf.is_empty() || [".", ".."].contains(leaf) {
    fail(
      "batch OUTPUT_DIR must name a new directory without a trailing separator",
    )
  }
  let text = @utf8.decode(read_limited_file(manifest, 65536))
  let plan = @fontpin.BatchPlan::parse(text)
  let font = @fontpin.Font::parse(read_font(source))
  let artifacts = font.instantiate_batch(plan)
  let outputs = artifacts.map(artifact => {
    "file": Json(artifact.filename),
    "font": artifact.instance.report_json(),
  })
  let report : Json = {
    "version": 1,
    "plan": plan.to_json(),
    "outputs": Json(outputs),
  }
  publish_batch(destination, artifacts, report)
  @stdio.stdout.write(report.stringify() + "\n")
}
