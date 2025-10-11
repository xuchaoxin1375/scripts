"""
Image Optimizer Module
======================

This module provides functionalities to compress JPEG and PNG images,
and convert images to the WebP format. It aims to reduce file sizes
significantly, making images suitable for web browsing, while maintaining
a good level of quality.

The module is built upon the Pillow library.

Features:
- Compress JPEG images with adjustable quality.
- Compress PNG images with optimization and adjustable compression level.
- Convert JPEG/PNG images to WebP format (lossy and lossless) with adjustable quality.
- Batch process images in a directory.
- Well-documented and designed for flexibility.

Requirements:
- Pillow: `pip install Pillow`
"""

import os
from typing import Any, Dict, List, Optional, Tuple

from PIL import Image


# --- Custom Exceptions ---
class ImageProcessingError(Exception):
    """Base exception for image processing errors in this module."""

    pass


class FileNotFoundError(ImageProcessingError):
    """Raised when an image file is not found."""

    pass


class UnsupportedFormatError(ImageProcessingError):
    """Raised when an unsupported image format is encountered."""

    pass


class OutputPathError(ImageProcessingError):
    """Raised for errors related to the output path."""

    pass


class ImageOptimizer:
    """
    A class to handle image compression and conversion.

    Provides methods to compress JPEG and PNG images, and convert
    images to WebP format. It also supports batch processing of
    images within a directory.
    """

    def __init__(self, default_jpeg_quality: int = 85, default_webp_quality: int = 80):
        """
        Initializes the ImageOptimizer.

        Args:
            default_jpeg_quality (int): Default quality for JPEG compression (1-95).
            default_webp_quality (int): Default quality for WebP conversion (1-100).
        """
        self.default_jpeg_quality = default_jpeg_quality
        self.default_webp_quality = default_webp_quality

    def _ensure_output_dir_exists(self, output_path: str) -> None:
        """
        Ensures the directory for the output path exists. Creates it if not.

        Args:
            output_path (str): The full path to the output file.

        Raises:
            OutputPathError: If the output directory cannot be created.
        """
        output_dir = os.path.dirname(output_path)
        if output_dir and not os.path.exists(output_dir):
            try:
                os.makedirs(output_dir, exist_ok=True)
            except OSError as e:
                raise OutputPathError(
                    f"Could not create output directory {output_dir}: {e}"
                )

    def compress_jpeg(
        self,
        input_path: str,
        output_path: str,
        quality: Optional[int] = None,
        optimize: bool = True,
        progressive: bool = True,
        **kwargs: Any,
    ) -> None:
        """
        Compresses a JPEG image.

        Args:
            input_path (str): Path to the input JPEG image.
            output_path (str): Path to save the compressed JPEG image.
            quality (Optional[int]): Compression quality (1-95). Higher is better.
                                     Defaults to `self.default_jpeg_quality`.
            optimize (bool): If True, an extra pass is made over the image
                             to select optimal encoder settings.
            progressive (bool): If True, save as a progressive JPEG.
            **kwargs: Additional keyword arguments to pass to `Image.save()`.

        Raises:
            FileNotFoundError: If the input file does not exist.
            ImageProcessingError: If any error occurs during processing.
            OutputPathError: If the output directory cannot be created.
        """
        if not os.path.exists(input_path):
            raise FileNotFoundError(f"Input file not found: {input_path}")

        quality = quality if quality is not None else self.default_jpeg_quality
        self._ensure_output_dir_exists(output_path)

        try:
            with Image.open(input_path) as img:
                # Ensure image is in RGB mode for JPEG
                if img.mode not in ("RGB", "L"):  # L for grayscale
                    img = img.convert("RGB")
                img.save(
                    output_path,
                    format="JPEG",
                    quality=quality,
                    optimize=optimize,
                    progressive=progressive,
                    **kwargs,
                )
            print(
                f"Successfully compressed JPEG: {input_path} -> {output_path} (Quality: {quality})"
            )
        except (
            FileNotFoundError
        ):  # Should be caught by the initial check, but good practice
            raise
        except Exception as e:
            raise ImageProcessingError(f"Error compressing JPEG {input_path}: {e}")

    def compress_png(
        self,
        input_path: str,
        output_path: str,
        optimize: bool = True,
        compress_level: int = 6,
        **kwargs: Any,
    ) -> None:
        """
        Compresses a PNG image.

        Args:
            input_path (str): Path to the input PNG image.
            output_path (str): Path to save the compressed PNG image.
            optimize (bool): If True, instructs the PNG writer to make the output file
                             as small as possible. This includes trying different filter
                             types and ZLIB compression levels.
            compress_level (int): ZLIB compression level (0-9). 0 is no compression,
                                  1 is fastest/worst compression, 9 is slowest/best.
                                  This is one of the parameters `optimize=True` will try.
            **kwargs: Additional keyword arguments to pass to `Image.save()`.

        Raises:
            FileNotFoundError: If the input file does not exist.
            ImageProcessingError: If any error occurs during processing.
            OutputPathError: If the output directory cannot be created.
        """
        if not os.path.exists(input_path):
            raise FileNotFoundError(f"Input file not found: {input_path}")

        self._ensure_output_dir_exists(output_path)

        try:
            with Image.open(input_path) as img:
                img.save(
                    output_path,
                    format="PNG",
                    optimize=optimize,
                    compress_level=compress_level,
                    **kwargs,
                )
            print(
                f"Successfully compressed PNG: {input_path} -> {output_path} (Optimize: {optimize}, Level: {compress_level})"
            )
        except FileNotFoundError:
            raise
        except Exception as e:
            raise ImageProcessingError(f"Error compressing PNG {input_path}: {e}")

    def convert_to_webp(
        self,
        input_path: str,
        output_path: str,
        quality: Optional[int] = None,
        lossless: bool = False,
        method: int = 4,
        **kwargs: Any,
    ) -> None:
        """
        Converts an image (JPEG, PNG) to WebP format.

        Args:
            input_path (str): Path to the input image (JPEG or PNG).
            output_path (str): Path to save the WebP image.
            quality (Optional[int]): For lossy WebP, quality (1-100). Higher is better.
                                     Defaults to `self.default_webp_quality`.
                                     For lossless WebP, this controls effort (0-100), higher is smaller/slower.
            lossless (bool): If True, use lossless WebP compression.
            method (int): Quality/speed trade-off (0=fastest, 6=slower/better).
                          Only used for lossy compression if `quality` is also specified.
                          For lossless, this parameter is related to compression effort.
            **kwargs: Additional keyword arguments to pass to `Image.save()`.

        Raises:
            FileNotFoundError: If the input file does not exist.
            UnsupportedFormatError: If the input image format is not JPEG or PNG.
            ImageProcessingError: If any error occurs during processing.
            OutputPathError: If the output directory cannot be created.
        """
        if not os.path.exists(input_path):
            raise FileNotFoundError(f"Input file not found: {input_path}")

        quality = quality if quality is not None else self.default_webp_quality
        self._ensure_output_dir_exists(output_path)

        try:
            with Image.open(input_path) as img:
                # Pillow's WebP save options:
                # quality: 0-100 (for lossy, higher is better; for lossless, higher is more effort)
                # lossless: True/False
                # method: 0 (fastest) to 6 (slowest, best compression).
                #         Pillow documentation suggests this is more for lossless,
                #         but it can influence lossy encoding too.
                save_options = {
                    "format": "WEBP",
                    "quality": quality,
                    "lossless": lossless,
                    "method": method,
                }
                save_options.update(
                    kwargs
                )  # Allow overriding with user-provided kwargs

                img.save(output_path, **save_options)
            print(
                f"Successfully converted to WebP: {input_path} -> {output_path} (Quality: {quality}, Lossless: {lossless})"
            )
        except FileNotFoundError:
            raise
        except Exception as e:
            # Check if it's an unsupported format by Pillow for WebP source
            if "encoder error" in str(e).lower() and "webp" in str(e).lower():
                raise UnsupportedFormatError(
                    f"Pillow WebP encoder error for {input_path}. Original error: {e}"
                )
            raise ImageProcessingError(f"Error converting {input_path} to WebP: {e}")

    def process_directory(
        self,
        input_dir: str,
        output_dir: str,
        operations: List[Tuple[str, Dict[str, Any]]],
        recursive: bool = False,
        skip_existing: bool = True,
    ) -> Tuple[int, int]:
        """
        Processes all supported images in a directory.

        Args:
            input_dir (str): Directory containing input images.
            output_dir (str): Directory to save processed images.
                              The original directory structure will be preserved.
            operations (List[Tuple[str, Dict[str, Any]]]): A list of operations to perform.
                Each operation is a tuple: (operation_name, params_dict).
                Supported operation_names: 'compress_jpeg', 'compress_png', 'to_webp'.
                Example: `[('compress_jpeg', {'quality': 75}), ('to_webp', {'quality': 70})]`
            recursive (bool): If True, process subdirectories recursively.
            skip_existing (bool): If True, skip processing if the output file already exists.

        Returns:
            Tuple[int, int]: Number of successfully processed files and number of failed files.

        Raises:
            FileNotFoundError: If the input directory does not exist.
        """
        if not os.path.isdir(input_dir):
            raise FileNotFoundError(f"Input directory not found: {input_dir}")

        if not os.path.exists(output_dir):
            os.makedirs(output_dir, exist_ok=True)

        success_count = 0
        failure_count = 0
        supported_formats = (".jpg", ".jpeg", ".png")

        for root, _, files in os.walk(input_dir):
            for filename in files:
                if not filename.lower().endswith(supported_formats):
                    continue

                input_path = os.path.join(root, filename)

                # Construct output path preserving directory structure
                relative_path = os.path.relpath(input_path, input_dir)
                current_output_dir = os.path.join(
                    output_dir, os.path.dirname(relative_path)
                )
                if not os.path.exists(current_output_dir):
                    os.makedirs(current_output_dir, exist_ok=True)

                base, ext = os.path.splitext(filename)
                ext = ext.lower()

                temp_input_path = input_path  # Path for the current operation's input

                for op_name, params in operations:
                    try:
                        # Determine output path for this specific operation
                        if op_name == "to_webp":
                            op_output_filename = f"{base}.webp"
                        else:  # compress_jpeg, compress_png
                            op_output_filename = (
                                f"{base}{ext}"  # Output has same extension
                            )

                        op_output_path = os.path.join(
                            current_output_dir, op_output_filename
                        )

                        if skip_existing and os.path.exists(op_output_path):
                            print(
                                f"Skipping {op_name} for {temp_input_path}, output exists: {op_output_path}"
                            )
                            temp_input_path = (
                                op_output_path  # Use this output as input for next op
                            )
                            continue

                        if op_name == "compress_jpeg" and ext in (".jpg", ".jpeg"):
                            self.compress_jpeg(
                                temp_input_path, op_output_path, **params
                            )
                        elif op_name == "compress_png" and ext == ".png":
                            self.compress_png(temp_input_path, op_output_path, **params)
                        elif op_name == "to_webp" and ext in (".jpg", ".jpeg", ".png"):
                            # If previous operation was compression, temp_input_path might be the compressed file
                            self.convert_to_webp(
                                temp_input_path, op_output_path, **params
                            )
                        else:
                            # Skip if operation doesn't match file type
                            # Or if it's an unknown operation
                            if op_name in ["compress_jpeg", "compress_png", "to_webp"]:
                                print(
                                    f"Skipping operation '{op_name}' for {temp_input_path} (mismatched format or already processed)."
                                )
                            else:
                                print(
                                    f"Unknown operation '{op_name}' for {temp_input_path}."
                                )
                            continue  # Skip to next operation for this file

                        temp_input_path = (
                            op_output_path  # Output of this op is input for next
                        )
                        success_count += 1  # Count per successful operation step
                    except Exception as e:
                        print(f"Failed to {op_name} {input_path}: {e}")
                        failure_count += 1
                        break  # Stop processing this file if one operation fails

            if not recursive:
                break  # Process only the top-level directory if not recursive

        return success_count, failure_count


# --- Example Usage ---
if __name__ == "__main__":
    # Create a dummy optimizer instance
    optimizer = ImageOptimizer(default_jpeg_quality=80, default_webp_quality=75)

    # --- Create dummy image files for testing ---
    # You should replace these with actual image paths
    os.makedirs("test_images/input", exist_ok=True)
    os.makedirs("test_images/output", exist_ok=True)

    try:
        # Create a dummy JPEG
        dummy_jpg_path = "test_images/input/sample.jpg"
        Image.new("RGB", (600, 400), color="red").save(dummy_jpg_path, "JPEG")
        print(f"Created dummy JPEG: {dummy_jpg_path}")

        # Create a dummy PNG
        dummy_png_path = "test_images/input/sample.png"
        Image.new("RGBA", (600, 400), color=(0, 255, 0, 128)).save(
            dummy_png_path, "PNG"
        )
        print(f"Created dummy PNG: {dummy_png_path}")
    except Exception as e:
        print(f"Error creating dummy images: {e}. Please ensure Pillow is installed.")
        exit()
    # --- End of dummy image creation ---

    # 1. Compress a JPEG image
    try:
        optimizer.compress_jpeg(
            dummy_jpg_path, "test_images/output/sample_compressed.jpg", quality=75
        )
    except Exception as e:
        print(f"Error in JPEG compression example: {e}")

    # 2. Compress a PNG image
    try:
        optimizer.compress_png(
            dummy_png_path, "test_images/output/sample_compressed.png", compress_level=7
        )
    except Exception as e:
        print(f"Error in PNG compression example: {e}")

    # 3. Convert a JPEG to WebP (lossy)
    try:
        optimizer.convert_to_webp(
            dummy_jpg_path, "test_images/output/sample_lossy.webp", quality=70
        )
    except Exception as e:
        print(f"Error in JPEG to WebP (lossy) example: {e}")

    # 4. Convert a PNG to WebP (lossless)
    try:
        optimizer.convert_to_webp(
            dummy_png_path,
            "test_images/output/sample_lossless.webp",
            lossless=True,
            quality=80,
        )  # quality for lossless is effort
    except Exception as e:
        print(f"Error in PNG to WebP (lossless) example: {e}")

    # 5. Convert a PNG to WebP (lossy)
    try:
        optimizer.convert_to_webp(
            dummy_png_path,
            "test_images/output/sample_png_lossy.webp",
            quality=65,
            lossless=False,
        )
    except Exception as e:
        print(f"Error in PNG to WebP (lossy) example: {e}")

    # 6. Batch process a directory
    # Create another dummy image for batch test
    try:
        os.makedirs("test_images/input/subdir", exist_ok=True)
        dummy_jpg2_path = "test_images/input/subdir/another.jpg"
        Image.new("RGB", (300, 200), color="blue").save(dummy_jpg2_path, "JPEG")
        print(f"Created dummy JPEG for batch: {dummy_jpg2_path}")
    except Exception as e:
        print(f"Error creating second dummy image: {e}")

    print("\n--- Batch Processing Example ---")
    batch_operations = [
        ("compress_jpeg", {"quality": 70}),  # Compress JPEGs first
        ("compress_png", {"compress_level": 8}),  # Compress PNGs
        ("to_webp", {"quality": 65, "lossless": False}),  # Then convert all to WebP
    ]
    try:
        # Note: The batch processor will apply operations sequentially.
        # If a JPEG is compressed, the compressed version is then converted to WebP.
        # If you want to convert original to WebP, run 'to_webp' as a separate batch call
        # or ensure 'temp_input_path' logic correctly handles your desired workflow.
        # The current logic uses the output of the previous operation as input for the next.
        success, failures = optimizer.process_directory(
            "test_images/input",
            "test_images/output_batch",
            operations=batch_operations,
            recursive=True,
            skip_existing=False,
        )
        print(f"Batch processing complete. Successes: {success}, Failures: {failures}")
    except Exception as e:
        print(f"Error in batch processing example: {e}")

    print(
        "\nCheck the 'test_images/output' and 'test_images/output_batch' directories for results."
    )
