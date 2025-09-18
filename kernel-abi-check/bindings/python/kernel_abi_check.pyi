"""Type stubs for kernel_abi_check module."""

from typing import List, Union
import os

__version__: str

class ObjectFile:
    """Object file that can be validated for ABI compatibility."""

    def __init__(self, filename: os.PathLike[str] | str) -> None:
        """Create a new ObjectFile from a path.

        Args:
            filename: Path to the object file to analyze

        Raises:
            IOError: If the file cannot be opened or read
        """
        ...

    def check_python_abi(
        self, abi_version: str
    ) -> List[Union[IncompatibleAbi3Symbol, NonAbi3Symbol]]:
        """Check Python stable ABI compatibility for this object file.

        Args:
            abi_version: Python ABI version string (e.g., "3.8")

        Returns:
            List of ABI violations found

        Raises:
            ValueError: If the ABI version cannot be parsed or ABI check fails
        """
        ...

    def check_manylinux(self, manylinux_version: str) -> List[ManylinuxSymbolViolation]:
        """Check manylinux compatibility for this object file.

        Args:
            manylinux_version: Manylinux version string (e.g., "manylinux_2_17")

        Returns:
            List of manylinux violations found

        Raises:
            ValueError: If the manylinux check fails
        """
        ...

    def check_macos(
        self, macos_version: str
    ) -> List[Union[MissingMinOS, IncompatibleMinOS]]:
        """Check macOS compatibility for this object file.

        Args:
            macos_version: macOS version string (e.g., "10.15")

        Returns:
            List of macOS violations found

        Raises:
            ValueError: If the macOS version cannot be parsed or check fails
        """
        ...

class IncompatibleAbi3Symbol:
    """ABI3 symbol that is not compatible with the specified Python ABI version."""

    @property
    def name(self) -> str:
        """Name of the symbol."""
        ...

    @property
    def version_added(self) -> str:
        """Version when this symbol was added to Python."""
        ...

    def __repr__(self) -> str: ...

class NonAbi3Symbol:
    """Python symbol that is not part of ABI3."""

    @property
    def name(self) -> str:
        """Name of the symbol."""
        ...

    def __repr__(self) -> str: ...

class ManylinuxSymbolViolation:
    """Symbol that is not allowed by the manylinux version."""

    @property
    def name(self) -> str:
        """Name of the symbol."""
        ...

    @property
    def dep(self) -> str:
        """Dependency that contains the symbol."""
        ...

    @property
    def version(self) -> str:
        """Version of the symbol."""
        ...

    def __repr__(self) -> str: ...

class MissingMinOS:
    """Object file does not specify minimum OS version."""

    def __repr__(self) -> str: ...

class IncompatibleMinOS:
    """The minimum OS version of the object file is higher than the
    specified macOS version."""

    @property
    def version(self) -> str:
        """Minimum OS version of the object file."""
        ...

    def __repr__(self) -> str: ...
