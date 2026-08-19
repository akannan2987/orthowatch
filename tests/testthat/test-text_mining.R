# test-text_mining.R — tokenization rules and rate-ratio arithmetic
# ===================================================================
# As always: tiny inputs, hand-worked answers, exact expectations.

test_that("tokenizer lowercases, drops filler/domain words, numbers, fragments", {
  ev <- tibble::tibble(
    report_number = "r1",
    device_family = "Hip prosthesis",
    narrative = "The PATIENT underwent Revision surgery on 2023. Metal debris at 45 mm."
  )
  tok <- tokenize_narratives(ev)
  expect_true(all(c("revision", "surgery", "metal", "debris") %in% tok$word))
  expect_false("the" %in% tok$word)        # standard stop word
  expect_false("patient" %in% tok$word)    # domain stop word
  expect_false("2023" %in% tok$word)       # bare number
  expect_false("45" %in% tok$word)
  expect_false("mm" %in% tok$word)         # < 3 characters
  expect_true(all(tok$word == tolower(tok$word)))
})

test_that("empty and NA narratives contribute nothing", {
  ev <- tibble::tibble(
    report_number = c("r1", "r2"),
    device_family = "Hip prosthesis",
    narrative = c("", NA)
  )
  expect_equal(nrow(tokenize_narratives(ev)), 0)
})

test_that("rate ratio matches the hand-worked example", {
  # Hand-worked: word appears 10x among the family's 100 words and
  # 5x among the others' 200 words. With the +0.5/+1 smoothing:
  #   rate_family = 10.5 / 101 = 0.1039604
  #   rate_others =  5.5 / 201 = 0.0273632
  #   ratio = 3.799289 ; log2 = 1.925730
  tc <- tibble::tibble(
    device_family = c("Hip prosthesis", "Hip prosthesis",
                      "Knee prosthesis", "Knee prosthesis"),
    word = c("metal", "filler", "metal", "filler"),
    n = c(10, 90, 5, 195)
  ) |>
    dplyr::group_by(device_family) |>
    dplyr::mutate(family_total = sum(n)) |>
    dplyr::ungroup()

  d <- distinctive_terms(tc, min_total = 1) |>
    dplyr::filter(device_family == "Hip prosthesis", word == "metal")
  expect_equal(d$rate_family, 10.5 / 101, tolerance = 1e-9)
  expect_equal(d$rate_others, 5.5 / 201,  tolerance = 1e-9)
  expect_equal(d$ratio,      3.799289,    tolerance = 1e-5)
  expect_equal(d$log2_ratio, 1.925730,    tolerance = 1e-5)
})

test_that("smoothing keeps a zero count finite and nonzero", {
  tc <- tibble::tibble(
    device_family = c("Hip prosthesis", "Knee prosthesis", "Knee prosthesis"),
    word = c("filler", "unique", "filler"),
    n = c(100, 50, 150)
  ) |>
    dplyr::group_by(device_family) |>
    dplyr::mutate(family_total = sum(n)) |>
    dplyr::ungroup()
  # "unique" never occurs in Hip — but Hip has no row for it at all,
  # so it simply doesn't appear for Hip (rate ratios are computed for
  # observed (family, word) pairs). For Knee, "filler" elsewhere is
  # 100 -> finite ratio; nothing divides by zero anywhere:
  d <- distinctive_terms(tc, min_total = 1)
  expect_true(all(is.finite(d$ratio)))
  expect_true(all(d$ratio > 0))
})
