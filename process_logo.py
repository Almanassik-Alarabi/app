import os
from PIL import Image, ImageDraw

def process_logo(input_path, output_path, size=(250, 250), radius=50):
    try:
        if not os.path.exists(input_path):
            print(f"Error: File {input_path} not found.")
            return

        with Image.open(input_path) as img:
            print(f"Original size: {img.size}")
            
            # Resize
            img.thumbnail(size, Image.ANTIALIAS if hasattr(Image, 'ANTIALIAS') else Image.Resampling.LANCZOS)
            
            # Create mask for rounded corners
            mask = Image.new('L', img.size, 0)
            draw = ImageDraw.Draw(mask)
            draw.rounded_rectangle([(0, 0), img.size], radius=radius, fill=255)
            
            # Apply mask
            result = img.copy()
            result.putalpha(mask)
            
            result.save(output_path)
            print(f"Processed image saved to {output_path}")
            print(f"New size: {result.size}")

    except Exception as e:
        print(f"Error processing image: {e}")

if __name__ == "__main__":
    input_file = '/home/djamel/AndroidStudioProjects/almanassik/android/app/src/main/res/drawable/splash_logo.png'
    # Overwrite the file
    process_logo(input_file, input_file)
