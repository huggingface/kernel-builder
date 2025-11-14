mod cpu;
pub use cpu::write_torch_ext_cpu;

mod cuda;
pub use cuda::write_torch_ext_cuda;

pub mod common;

mod metal;
pub use metal::write_torch_ext_metal;

mod ops_identifier;
pub(crate) use ops_identifier::kernel_ops_identifier;

mod universal;
pub use universal::write_torch_ext_universal;

mod xpu;
pub use xpu::write_torch_ext_xpu;
