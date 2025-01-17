compute_grob_widths <- function(grob_layout, widths) {
  cols <- split(grob_layout, grob_layout$l)
  widths <- lapply(cols, compute_grob_dimensions, dims = widths)
  inject(unit.c(!!!widths))
}

compute_grob_heights <- function(grob_layout, heights) {
  cols <- split(grob_layout, grob_layout$t)
  heights <- lapply(cols, compute_grob_dimensions, dims = heights)
  inject(unit.c(!!!heights))
}

compute_grob_dimensions <- function(grob_layout, dims) {
  # If any don't have explicit dims, then width is NULL
  if (!any(grob_layout$type %in% names(dims))) {
    return(unit(1, "null"))
  }

  grob_layout <- grob_layout[grob_layout$type %in% names(dims), , drop = FALSE]

  dims <- unique0(Map(function(type, pos) {
    type_width <- dims[[type]]
    if (length(type_width) == 1) type_width else type_width[pos]
  }, grob_layout$type, grob_layout$id))
  units <- vapply(dims, is.unit, logical(1))

  if (all(units)) {
    if (all(lapply(dims, attr, "unit") == "null")) unit(max(unlist(dims)), "null")
    else inject(max(!!!dims))
  } else {
    raw_max <- unit(max(unlist(dims[!units])), "cm")
    if (any(units)) {
      unit_max <- max(inject(unit.c(!!!dims[units])))
      max(raw_max, unit_max)
    }
    else {
      raw_max
    }
  }
}
