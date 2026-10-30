///|
pub(all) suberror FontError {
  Invalid(String)
  Unsupported(String)
  Limit(String)
}

///|
pub struct Axis {
  tag : String
  minimum : Double
  default : Double
  maximum : Double
} derive(ToJson)

///|
pub extend Axis with ToJson::{to_json}

///|
pub struct Font {
  priv tables : Map[String, Bytes]
  priv design_axes : Array[Axis]
}

///|
pub struct Instance {
  priv data : Bytes
  priv coordinates : Map[String, Double]
  priv glyph_count : Int32
  priv layout : LayoutAudit
}

///|
pub fn Font::axes(self : Font) -> Array[Axis] {
  self.design_axes.copy()
}

///|
pub fn Instance::to_bytes(self : Instance) -> Bytes {
  self.data
}

///|
pub fn Instance::report_json(self : Instance) -> Json {
  {
    "glyph_count": Json(self.glyph_count),
    "coordinates": Json(self.coordinates),
    "bytes": Json(self.data.length()),
    "layout": self.layout_report(),
  }
}

///|
pub fn FontError::message(self : FontError) -> String {
  match self {
    Invalid(detail) => "invalid font: " + detail
    Unsupported(detail) => "unsupported font: " + detail
    Limit(detail) => "resource limit: " + detail
  }
}
