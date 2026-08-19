/// Shared weight calculation — the ONE implementation of Net = Gross −
/// Empty used everywhere this pattern appears (previously duplicated
/// inline as a private getter in batch_pickup_screen.dart's Delivery
/// Challan entry; now also used by Quick Entry's optional Box/Gross/
/// Empty Weight fields). Never negative — a data-entry mistake (empty
/// weight typed larger than gross) clamps to 0 rather than producing a
/// negative net weight.
class WeightCalc {
  const WeightCalc._();

  static double net(double gross, double empty) =>
      (gross - empty).clamp(0, double.infinity);
}