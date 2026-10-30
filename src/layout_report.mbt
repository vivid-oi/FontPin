///|
priv struct LayoutAudit {
  gdef_indices : Int32
  gpos_indices : Int32
  lookup_types : Array[Int32]
  features : Array[(String, Bool, Int32?)]
  rewritten : Array[String]
}

///|
/// Return detached layout-instancing evidence (schema version 1).
/// Counts describe visited VariationIndex references, including zero deltas and
/// NO_VARIATION_INDEX sentinels, not distinct store rows or shaped text.
pub fn Instance::layout_report(self : Instance) -> Json {
  let audit = self.layout
  let features : Map[String, Json] = Map([])
  for (tag, present, selected) in audit.features {
    features[tag] = {
      "present": Json(present),
      "record": match selected {
        Some(index) => Json(index)
        None => null
      },
    }
  }
  {
    "version": 1,
    "variation_indices": {
      "GDEF": Json(audit.gdef_indices),
      "GPOS": Json(audit.gpos_indices),
    },
    "gpos_lookup_types": Json(audit.lookup_types.copy()),
    "feature_variations": Json::object(features),
    "rewritten_tables": Json(audit.rewritten.copy()),
  }
}
