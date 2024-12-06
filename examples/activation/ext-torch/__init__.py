import torch

try:
    from ._ops import ops
except ImportError as e:
    # Fallback for local development.
    try:
        import _activation
        ops = torch.ops._activition
    except ImportError:
        raise e
    

def silu_and_mul(out: torch.Tensor, x: torch.Tensor) -> None:                                                                                                                                                                           
    ops.silu_and_mul(out, x)                                                                                                                                                                                                   
                                                                                                                                                                                                                                        
                                                                                                                                                                                                                                        
def gelu_and_mul(out: torch.Tensor, x: torch.Tensor) -> None:                                                                                                                                                                           
    ops.gelu_and_mul(out, x)                                                                                                                                                                                                   
                                                                                                                                                                                                                                        
                                                                                                                                                                                                                                        
def gelu_tanh_and_mul(out: torch.Tensor, x: torch.Tensor) -> None:                                                                                                                                                                      
    ops.gelu_tanh_and_mul(out, x)                                                                                                                                                                                              
                                                                                                                                                                                                                                        
                                                                                                                                                                                                                                        
def fatrelu_and_mul(out: torch.Tensor,                                                                                                                                                                                                  
                    x: torch.Tensor,                                                                                                                                                                                                    
                    threshold: float = 0.0) -> None:                                                                                                                                                                                    
    ops.fatrelu_and_mul(out, x, threshold)                                                                                                                                                                                     
                                                                                                                                                                                                                                        
                                                                                                                                                                                                                                        
def gelu_fast(out: torch.Tensor, x: torch.Tensor) -> None:                                                                                                                                                                              
    ops.gelu_fast(out, x)                                                                                                                                                                                                      
                                                                                                                                                                                                                                        
                                                                                                                                                                                                                                        
def gelu_new(out: torch.Tensor, x: torch.Tensor) -> None:                                                                                                                                                                               
    ops.gelu_new(out, x)                                                                                                                                                                                                       
                                                                                                                                                                                                                                        
                                                                                                                                                                                                                                        
def gelu_quick(out: torch.Tensor, x: torch.Tensor) -> None:                                                                                                                                                                             
    ops.gelu_quick(out, x)
