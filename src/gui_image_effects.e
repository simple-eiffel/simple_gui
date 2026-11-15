note
	description: "[
		Image effects (1z-a), all in shared code on simple_image: each takes an IMG_IMAGE and
		gives back a new one, so the pixels are identical on all three platforms. Show a result
		with `GUI_IMAGE.set_image', `GUI_IMAGE_VIEW.set_image' or a lightbox.

		grayscale (Rec. 709 luma, alpha kept), rounded and circled (avatars: corners cut,
		antialiased) are simple_image's integer kernels, the same bytes everywhere; blur,
		brightness, contrast, saturation and the vignette are its filters, applied to a copy.
	]"

class
	GUI_IMAGE_EFFECTS

feature -- Shapes and color

	grayscale (an_image: IMG_IMAGE): IMG_IMAGE
			-- `an_image' in shades of gray: Rec. 709 luma, alpha kept.
		require
			usable: an_image.is_usable
		do
			Result := an_image.grayscale
		ensure
			new: Result /= an_image
			same_size: same_size (Result, an_image)
		end

	rounded (an_image: IMG_IMAGE; a_radius: INTEGER): IMG_IMAGE
			-- `an_image' with its corners cut round to `a_radius' pixels (at most half the shorter
			-- side), antialiased; outside is transparent.
		require
			usable: an_image.is_usable
			radius_not_negative: a_radius >= 0
		do
			Result := an_image.rounded (a_radius)
		ensure
			new: Result /= an_image
			same_size: same_size (Result, an_image)
		end

	circled (an_image: IMG_IMAGE): IMG_IMAGE
			-- Only the largest centered circle of `an_image' (an avatar), antialiased; outside is
			-- transparent.
		require
			usable: an_image.is_usable
		do
			Result := an_image.circled
		ensure
			new: Result /= an_image
			same_size: same_size (Result, an_image)
		end

feature -- Filters

	blurred (an_image: IMG_IMAGE; a_radius: INTEGER): IMG_IMAGE
			-- `an_image' blurred with three box passes of `a_radius' (close to a gaussian of that
			-- sigma); 0 gives a plain copy.
		require
			usable: an_image.is_usable
			radius_not_negative: a_radius >= 0
		do
			Result := an_image.twin
			Result.blur (a_radius)
		ensure
			new: Result /= an_image
			same_size: same_size (Result, an_image)
		end

	brightened (an_image: IMG_IMAGE; a_factor: REAL_64): IMG_IMAGE
			-- `an_image' with its brightness scaled by `a_factor' (0 black, 1 unchanged).
		require
			usable: an_image.is_usable
			factor_not_negative: a_factor >= 0.0
		do
			Result := an_image.twin
			Result.enhance_brightness (a_factor)
		ensure
			new: Result /= an_image
			same_size: same_size (Result, an_image)
		end

	contrasted (an_image: IMG_IMAGE; a_factor: REAL_64): IMG_IMAGE
			-- `an_image' with its contrast scaled by `a_factor' about the mean gray (0 flat gray,
			-- 1 unchanged).
		require
			usable: an_image.is_usable
			factor_not_negative: a_factor >= 0.0
		do
			Result := an_image.twin
			Result.enhance_contrast (a_factor)
		ensure
			new: Result /= an_image
			same_size: same_size (Result, an_image)
		end

	saturated (an_image: IMG_IMAGE; a_factor: REAL_64): IMG_IMAGE
			-- `an_image' with its saturation scaled by `a_factor' (0 gray, 1 unchanged).
		require
			usable: an_image.is_usable
			factor_not_negative: a_factor >= 0.0
		do
			Result := an_image.twin
			Result.enhance_color (a_factor)
		ensure
			new: Result /= an_image
			same_size: same_size (Result, an_image)
		end

	vignetted (an_image: IMG_IMAGE; a_strength: REAL_64): IMG_IMAGE
			-- `an_image' darkened toward the corners: a corner keeps 1 - `a_strength' of its
			-- brightness.
		require
			usable: an_image.is_usable
			strength_in_range: 0.0 <= a_strength and a_strength <= 1.0
		do
			Result := an_image.twin
			Result.vignette (a_strength)
		ensure
			new: Result /= an_image
			same_size: same_size (Result, an_image)
		end

feature -- Status

	same_size (an_image, an_other: IMG_IMAGE): BOOLEAN
			-- Are the two the same width and height?
		do
			Result := an_image.width = an_other.width and an_image.height = an_other.height
		end

end
