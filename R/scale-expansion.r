
#' Generate expansion vector for scales
#'
#' This is a convenience function for generating scale expansion vectors
#' for the `expand` argument of [scale_(x|y)_continuous][scale_x_continuous()]
#' and [scale_(x|y)_discrete][scale_x_discrete()]. The expansion vectors are used to
#' add some space between the data and the axes.
#'
#' @param mult vector of multiplicative range expansion factors.
#'   If length 1, both the lower and upper limits of the scale
#'   are expanded outwards by `mult`. If length 2, the lower limit
#'   is expanded by `mult[1]` and the upper limit by `mult[2]`.
#' @param add vector of additive range expansion constants.
#'   If length 1, both the lower and upper limits of the scale
#'   are expanded outwards by `add` units. If length 2, the
#'   lower limit is expanded by `add[1]` and the upper
#'   limit by `add[2]`.
#'
#' @export
#' @examples
#' # No space below the bars but 10% above them
#' ggplot(mtcars) +
#'   geom_bar(aes(x = factor(cyl))) +
#'   scale_y_continuous(expand = expansion(mult = c(0, .1)))
#'
#' # Add 2 units of space on the left and right of the data
#' ggplot(subset(diamonds, carat > 2), aes(cut, clarity)) +
#'   geom_jitter() +
#'   scale_x_discrete(expand = expansion(add = 2))
#'
#' # Reproduce the default range expansion used
#' # when the 'expand' argument is not specified
#' ggplot(subset(diamonds, carat > 2), aes(cut, price)) +
#'   geom_jitter() +
#'   scale_x_discrete(expand = expansion(add = .6)) +
#'   scale_y_continuous(expand = expansion(mult = .05))
#'
expansion <- function(mult = 0, add = 0) {
  if (!(is.numeric(mult) && (length(mult) %in% 1:2) && is.numeric(add) && (length(add) %in% 1:2))) {
    abort("`mult` and `add` must be numeric vectors with 1 or 2 elements")
  }

  mult <- rep(mult, length.out = 2)
  add <- rep(add, length.out = 2)
  c(mult[1], add[1], mult[2], add[2])
}

#' @rdname expansion
#' @export
expand_scale <- function(mult = 0, add = 0) {
  .Deprecated(msg = "`expand_scale()` is deprecated; use `expansion()` instead.")
  expansion(mult, add)
}

#' Expand a numeric range
#'
#' @param limits A numeric vector of length 2 giving the
#'   range to expand.
#' @param expand A numeric vector of length 2 (`c(add, mult)`)
#'   or length 4 (`c(mult_left, add_left, mult_right, add_right)`),
#'   as generated by [expansion()].
#'
#' @return The expanded `limits`
#'
#' @noRd
#'
expand_range4 <- function(limits, expand) {
  if (!(is.numeric(expand) && length(expand) %in% c(2,4))) {
    abort("`expand` must be a numeric vector with 1 or 2 elements")
  }

  if (all(!is.finite(limits))) {
    return(c(-Inf, Inf))
  }

  # If only two expansion constants are given (i.e. the old syntax),
  # reuse them to generate a four-element expansion vector
  if (length(expand) == 2) {
    expand <- c(expand, expand)
  }

  # Calculate separate range expansion for the lower and
  # upper range limits, and then combine them into one vector
  lower <- expand_range(limits, expand[1], expand[2])[1]
  upper <- expand_range(limits, expand[3], expand[4])[2]
  c(lower, upper)
}

#' Calculate the default expansion for a scale
#'
#' @param scale A position scale (e.g., [scale_x_continuous()] or [scale_x_discrete()])
#' @param discrete,continuous Default scale expansion factors for
#'   discrete and continuous scales, respectively.
#' @param expand Should any expansion be applied?
#'
#' @return One of `discrete`, `continuous`, or `scale$expand`
#' @noRd
#'
default_expansion <- function(scale, discrete = expansion(add = 0.6),
                              continuous = expansion(mult = 0.05), expand = TRUE) {
  if (!expand) {
    return(expansion(0, 0))
  }

  scale$expand %|W|% if (scale$is_discrete()) discrete else continuous
}

#' Expand limits in (possibly) transformed space
#'
#' These functions calculate the continuous range in coordinate space
#' and in scale space. Usually these can be calculated from
#' each other using the coordinate system transformation, except
#' when transforming and expanding the scale limits results in values outside
#' the domain of the transformation (e.g., a lower limit of 0 with a square root
#' transformation).
#'
#' @param scale A position scale (see [scale_x_continuous()] and [scale_x_discrete()])
#' @param limits The initial scale limits, in scale-transformed space.
#' @param coord_limits The user-provided limits in scale-transformed space,
#'   which may include one more more NA values, in which case those limits
#'   will fall back to the `limits`. In `expand_limits_scale()`, `coord_limits`
#'   are in user data space and can be `NULL` (unspecified), since the transformation
#'   from user to mapped space is different for each scale.
#' @param expand An expansion generated by [expansion()] or [default_expansion()].
#' @param trans The coordinate system transformation.
#'
#' @return A list with components `continuous_range`, which is the
#'   expanded range in scale-transformed space, and `continuous_range_coord`,
#'   which is the expanded range in coordinate-transformed space.
#'
#' @noRd
#'
expand_limits_scale <- function(scale, expand = expansion(0, 0), limits = waiver(),
                                coord_limits = NULL) {
  limits <- limits %|W|% scale$get_limits()

  if (scale$is_discrete()) {
    coord_limits <- coord_limits %||% c(NA_real_, NA_real_)
    expand_limits_discrete(
      limits,
      expand,
      coord_limits,
      range_continuous = scale$range_c$range
    )
  } else {
    # using the inverse transform to resolve the NA value is needed for date/datetime/time
    # scales, which refuse to transform objects of the incorrect type
    coord_limits <- coord_limits %||% scale$trans$inverse(c(NA_real_, NA_real_))
    coord_limits_scale <- scale$trans$transform(coord_limits)
    expand_limits_continuous(limits, expand, coord_limits_scale)
  }
}

expand_limits_continuous <- function(limits, expand = expansion(0, 0), coord_limits = c(NA, NA)) {
  expand_limits_continuous_trans(limits, expand, coord_limits)$continuous_range
}

expand_limits_discrete <- function(limits, expand = expansion(0, 0), coord_limits = c(NA, NA),
                                   range_continuous = NULL) {
  limit_info <- expand_limits_discrete_trans(
    limits,
    expand,
    coord_limits,
    range_continuous = range_continuous
  )

  limit_info$continuous_range
}

expand_limits_continuous_trans <- function(limits, expand = expansion(0, 0),
                                           coord_limits = c(NA, NA), trans = identity_trans()) {

  # let non-NA coord_limits override the scale limits
  limits <- ifelse(is.na(coord_limits), limits, coord_limits)

  # expand limits in coordinate space
  continuous_range_coord <- trans$transform(limits)

  # range expansion expects values in increasing order, which may not be true
  # for reciprocal/reverse transformations
  if (all(is.finite(continuous_range_coord)) && diff(continuous_range_coord) < 0) {
    continuous_range_coord <- rev(expand_range4(rev(continuous_range_coord), expand))
  } else {
    continuous_range_coord <- expand_range4(continuous_range_coord, expand)
  }

  final_scale_limits <- trans$inverse(continuous_range_coord)

  # if any non-finite values were introduced in the transformations,
  # replace them with the original scale limits for the purposes of
  # calculating breaks and minor breaks from the scale
  continuous_range <- ifelse(is.finite(final_scale_limits), final_scale_limits, limits)

  list(
    continuous_range_coord = continuous_range_coord,
    continuous_range = continuous_range
  )
}

expand_limits_discrete_trans <- function(limits, expand = expansion(0, 0),
                                         coord_limits = c(NA, NA), trans = identity_trans(),
                                         range_continuous = NULL) {

  n_limits <- length(limits)
  is_empty <- is.null(limits) && is.null(range_continuous)
  is_only_continuous <- n_limits == 0
  is_only_discrete <- is.null(range_continuous)

  if (is_empty) {
    expand_limits_continuous_trans(c(0, 1), expand, coord_limits, trans)
  } else if (is_only_continuous) {
    expand_limits_continuous_trans(range_continuous, expand, coord_limits, trans)
  } else if (is_only_discrete) {
    expand_limits_continuous_trans(c(1, n_limits), expand, coord_limits, trans)
  } else {
    # continuous and discrete
    limit_info_discrete <- expand_limits_continuous_trans(c(1, n_limits), expand, coord_limits, trans)

    # don't expand continuous range if there is also a discrete range
    limit_info_continuous <- expand_limits_continuous_trans(
      range_continuous, expansion(0, 0), coord_limits, trans
    )

    # prefer expanded discrete range, but allow continuous range to further expand the range
    list(
      continuous_range_coord = range(
        c(limit_info_discrete$continuous_range_coord, limit_info_continuous$continuous_range_coord)
      ),
      continuous_range = range(
        c(limit_info_discrete$continuous_range, limit_info_continuous$continuous_range)
      )
    )
  }
}
