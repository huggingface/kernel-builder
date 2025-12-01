use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[non_exhaustive]
#[serde(rename_all = "lowercase")]
pub enum Dependency {
    #[serde(rename = "cutlass_2_10")]
    Cutlass2_10,
    #[serde(rename = "cutlass_3_5")]
    Cutlass3_5,
    #[serde(rename = "cutlass_3_6")]
    Cutlass3_6,
    #[serde(rename = "cutlass_3_8")]
    Cutlass3_8,
    #[serde(rename = "cutlass_3_9")]
    Cutlass3_9,
    #[serde(rename = "cutlass_4_0")]
    Cutlass4_0,
    #[serde(rename = "cutlass_sycl")]
    CutlassSycl,
    #[serde(rename = "metal-cpp")]
    MetalCpp,
    Torch,
}
