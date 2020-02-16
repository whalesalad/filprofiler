import numpy as np

from skimage import data
from skimage.feature import register_translation
from skimage.feature.register_translation import _upsampled_dft
from scipy.ndimage import fourier_shift
from skimage.transform import rescale

image = data.camera()
image = rescale(image, 8, anti_aliasing=True)

shift = (-22.4, 13.32)
# The shift corresponds to the pixel offset relative to the reference image
offset_image = fourier_shift(np.fft.fftn(image), shift)
offset_image = np.fft.ifftn(offset_image)
print(f"Known offset (y, x): {shift}")

# pixel precision first
shift, error, diffphase = register_translation(image, offset_image)

# Show the output of a cross-correlation to show what the algorithm is
# doing behind the scenes
image_product = np.fft.fft2(image) * np.fft.fft2(offset_image).conj()
cc_image = np.fft.fftshift(np.fft.ifft2(image_product))

print(f"Detected pixel offset (y, x): {shift}")

# subpixel precision
shift, error, diffphase = register_translation(image, offset_image, 100)

# Calculate the upsampled DFT, again to show what the algorithm is doing
# behind the scenes.  Constants correspond to calculated values in routine.
# See source code for details.
cc_image = _upsampled_dft(image_product, 150, 100, (shift*100)+75).conj()

print(f"Detected subpixel offset (y, x): {shift}")
