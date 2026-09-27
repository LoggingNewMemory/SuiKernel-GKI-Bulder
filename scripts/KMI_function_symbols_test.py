#!/usr/bin/env python3
# encoding: utf-8

"""
Compare symbols between abi_gki_aarch64.xml and vmlinux.symvers files.
"""

import sys
import argparse
from typing import Final, Set
from pathlib import Path

from lxml import etree

def setup_arg_parser() -> argparse.ArgumentParser:
    """Set up command-line argument parser."""
    parser = argparse.ArgumentParser(
        description="Compare symbols between abi_gki_aarch64.xml and vmlinux.symvers files."
    )
    parser.add_argument(
        'xml_file',
        type=str,
        help='Path to abi_gki_aarch64.xml file'
    )
    parser.add_argument(
        'symvers_file',
        type=str,
        help='Path to vmlinux.symvers file'
    )
    return parser

def read_xml_symbols(xml_file: Path) -> Set[str]:
    """Read symbols from the XML file."""
    with open(xml_file, 'r', encoding='utf-8') as f:
        xml_obj = etree.parse(f).getroot()
        return {
            elf_symbol.get("name")
            for elf_symbol in xml_obj.xpath(
                './/elf-function-symbols/elf-symbol | .//elf-variable-symbols/elf-symbol'
            )
        }

def read_symvers_symbols(symvers_file: Path) -> Set[str]:
    """Read symbols from the symvers file."""
    with open(symvers_file, 'r', encoding='utf-8') as f:
        return {
            line.split()[1]
            for line in f
            if len(line.split()) >= 2 and not line.startswith('#')
        }

def compare_symbols(xml_file: Path, symvers_file: Path) -> int:
    """Compare symbols between XML and symvers files."""
    # Validate file existence
    if not xml_file.is_file():
        print(f"Error: XML file not found: {xml_file}")
        return 1
    if not symvers_file.is_file():
        print(f"Error: Symvers file not found: {symvers_file}")
        return 1

    try:
        # Read symbols
        abi_symbols = read_xml_symbols(xml_file)
        symvers_symbols = read_symvers_symbols(symvers_file)

        # Compare symbols
        missing_symbols = abi_symbols - symvers_symbols

        if not missing_symbols:
            print("\nAll symbols found in Module.symvers.\n")
            return 0

        print("\nMissing symbols from Module.symvers:")
        for symbol in sorted(missing_symbols):
            print(f"- {symbol}")
        print("")
        return 0

    except Exception as e:
        print(f"An error occurred: {e}")
        return 1

def main() -> int:
    """Main function to run the symbol comparison."""
    parser = setup_arg_parser()
    args = parser.parse_args()

    xml_file = Path(args.xml_file)
    symvers_file = Path(args.symvers_file)

    return compare_symbols(xml_file, symvers_file)

if __name__ == "__main__":
    sys.exit(main())
