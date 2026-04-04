from PIL import Image

def pad_image(src, dst, scale_factor, bg_color=(19, 19, 31, 255)):
    # 0xFF13131F is (19, 19, 31)
    img = Image.open(src).convert("RGBA")
    
    # Calculate new scaled size
    new_w = int(img.width * scale_factor)
    new_h = int(img.height * scale_factor)
    
    scaled_img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    
    # Create background canvas
    canvas = Image.new("RGBA", (img.width, img.height), bg_color)
    
    # Paste centered (using the alpha channel as a mask)
    offset_x = (img.width - new_w) // 2
    offset_y = (img.height - new_h) // 2
    canvas.paste(scaled_img, (offset_x, offset_y), scaled_img)
    
    canvas.save(dst)
    print(f"Saved {dst}")

import os

# Base path
base = "c:/Users/Dhruv/Desktop/Kynetix/kynetix_ui/assets/branding/"

pad_image(base+"kynetix_icon.png", base+"kynetix_icon_padded.png", 0.60, (0, 0, 0, 0))
pad_image(base+"kynetix_icon.png", base+"kynetix_icon_fg.png", 0.66, (0, 0, 0, 0))
pad_image(base+"kynetix_logo.png", base+"kynetix_logo_padded.png", 0.50, (19, 19, 31, 255))
