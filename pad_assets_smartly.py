from PIL import Image
import os

def pad_opaque(src, dst, scale_factor):
    img = Image.open(src).convert("RGBA")
    bg_color = img.getpixel((0,0)) # intelligently extract native background
    
    new_w = int(img.width * scale_factor)
    new_h = int(img.height * scale_factor)
    scaled_img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    
    canvas = Image.new("RGBA", (img.width, img.height), bg_color)
    offset_x = (img.width - new_w) // 2
    offset_y = (img.height - new_h) // 2
    # Paste using no mask if it's opaque, or itself as mask if it has some partial transparency
    canvas.paste(scaled_img, (offset_x, offset_y))
    
    canvas.save(dst)
    print(f"Saved opaque {dst} with bg {bg_color}")

def pad_transparent(src, dst, scale_factor):
    img = Image.open(src).convert("RGBA")
    
    new_w = int(img.width * scale_factor)
    new_h = int(img.height * scale_factor)
    scaled_img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    
    canvas = Image.new("RGBA", (img.width, img.height), (0,0,0,0))
    offset_x = (img.width - new_w) // 2
    offset_y = (img.height - new_h) // 2
    canvas.paste(scaled_img, (offset_x, offset_y), scaled_img)
    
    canvas.save(dst)
    print(f"Saved transparent {dst}")

base = "c:/Users/Dhruv/Desktop/Kynetix/kynetix_ui/assets/branding/"

# Kynetix Icon has NO transparency (Scale 0.66 prevents clipping in Android squircle)
pad_opaque(base+"kynetix_icon.png", base+"kynetix_icon_fg.png", 0.66)
# Splash needs to prevent massive zoom in android_12 (Scale 0.6 is safe)
pad_opaque(base+"kynetix_icon.png", base+"kynetix_icon_padded.png", 0.60)

# Kynetix Logo HAS transparency
pad_transparent(base+"kynetix_logo.png", base+"kynetix_logo_padded.png", 0.50)
