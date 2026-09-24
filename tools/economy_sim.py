#!/usr/bin/env python3
"""
Smart-scheduling economy simulator for dizain_hunter.md v1.5.

Each must-buy item has a deadline (the latest stage by which it must be owned).
On every stage the player first buys all due items (greedy: cheapest first to
minimise blocking risk). If any leftover budget remains, an optional pre-buy of
upcoming-deadline items is performed, capped by a safety buffer.

Exits 0 on PASS, 1 on FAIL.
"""

from dataclasses import dataclass, field
from typing import List


# ── Stages ────────────────────────────────────────────────────────────────────

STAGE_NAMES = [
    "Ученик→Подмастерье",
    "Подмастерье→Охотник",
    "Охотник→Ветеран",
    "Ветеран→Мастер",
    "Мастер→Легенда",
]

# Доход по этапам после β.1+β.2 правок (§4 design-decisions).
# Базовая разбивка — §12.12 спецификации; повышена за счёт β.1 на ранних зверях.
# Суммарно ≈ 622 (целевой 620 ± корректировки β.1).
INCOME_DELTA = [
    22,   # Ученик→Подмастерье: 1 Хруз после β.1 (mid=21.5)
    75,   # Подмастерье→Охотник: 3 Шипуна после β.1 (~25 каждый)
    140,  # Охотник→Ветеран: 3 Громуна после β.1 + 1 Тлеун (~35*3 + ~35)
    335,  # Ветеран→Мастер: β.3 максимум — Скорб~70×2 + Пепел-Мать~80×2 + мелочь
    195,  # Мастер→Легенда: 1 Ламент (~165) + побочный фарм
]
assert sum(INCOME_DELTA) == 767, f"income mismatch: {sum(INCOME_DELTA)}"


@dataclass
class Item:
    name: str
    cost: int
    deadline_stage: int   # Must own by END of this stage (index into STAGE_NAMES)


@dataclass
class BuyRecord:
    name: str
    cost: int
    stage_bought: int


# ── A-narrowed must-buy после β-правок (§3 design-decisions) ────────────────
# Дедлайн = этап, к концу которого предмет должен быть у игрока.

ITEMS: List[Item] = [
    # Подмастерье: базовое снаряжение и первый навыковый уровень
    Item("Опорный сигнал (Чтение L1)",      16, deadline_stage=1),
    Item("+1 урон (Оружие L1)",             20, deadline_stage=1),
    Item("+1 броня (Выживание L1)",         20, deadline_stage=2),  # отложен: Шипуна бьём без +1 брони
    Item("Лёгкая броня",                    12, deadline_stage=2),  # отложена: бьём Громуна уворотом
    Item("Клинок",                          16, deadline_stage=1),
    Item("Совет Старика: Шипун",             4, deadline_stage=1),

    # Охотник: средний слой; руна_огня полезна, но не критична (можно отложить)
    Item("Двойной опорный (Чтение L2)",     40, deadline_stage=2),
    Item("+2 урон (Оружие L2)",             45, deadline_stage=3),  # отложен: Громуна/Тлеуна бьём на +1
    Item("Лук",                             20, deadline_stage=2),
    Item("Арбалет",                         30, deadline_stage=2),
    Item("Руна огня",                       20, deadline_stage=3),  # отложена до Ветерана
    Item("Совет Старика: Громун",           10, deadline_stage=2),
    Item("Совет Старика: Тлеун",            10, deadline_stage=2),

    # Ветеран: продвинутый слой под Ламента
    Item("Тройной опорный (Чтение L3)",     60, deadline_stage=3),
    Item("+3 урон (Оружие L3)",             70, deadline_stage=3),
    Item("+2 броня (Выживание L2)",         45, deadline_stage=3),
    Item("Дробящий",                        25, deadline_stage=4),  # отложен: Пепел-Мать бьём Клинком/Луком
    Item("Руна яда",                        65, deadline_stage=3),
    Item("Тяжёлая броня",                   40, deadline_stage=4),  # отложена: до финального боя
    Item("Совет Старика: Скорб",            15, deadline_stage=3),
    Item("Совет Старика: Пепел-Мать",       15, deadline_stage=3),

    # Мастер: финальные штрихи перед Ламентом
    Item("+3 броня (Выживание L3)",         70, deadline_stage=4),
    Item("Совет Старика: Ламент",           25, deadline_stage=4),
]


SAFETY_BUFFER = 30   # Не тратить ниже этого порога при early-buy.


def simulate() -> bool:
    balance = 0
    cumulative_income = 0
    spent_so_far: List[BuyRecord] = []
    remaining = {i.name: i for i in ITEMS}

    header = (f"{'Этап':<24}{'+доход':>8}{'=баланс':>11}"
              f"{'spent stage':>15}{'итого потрачено':>22}")
    print(header)
    print("-" * len(header.encode("utf-8")))

    for idx, stage_name in enumerate(STAGE_NAMES):
        # Income at start of stage transition
        income = INCOME_DELTA[idx]
        balance += income
        cumulative_income += income

        # 1. Mandatory buys: everything whose deadline == this stage
        due_today = sorted(
            [i for i in ITEMS if i.deadline_stage == idx and i.name in remaining],
            key=lambda x: x.cost,
        )
        spent_this_stage = 0

        for it in due_today:
            if balance < it.cost:
                print(f"!!! FAIL на '{stage_name}': "
                      f"нет {it.cost} монет на '{it.name}' (balance={balance}).")
                print(f"    Дефицит: {it.cost - balance}. "
                      f"Куплено до этого момента: {len(spent_so_far)} предметов.")
                return False
            balance -= it.cost
            spent_this_stage += it.cost
            spent_so_far.append(BuyRecord(it.name, it.cost, idx))
            del remaining[it.name]

        # 2. Optional early-buy: take upcoming deadlines if we have spare money
        # above the safety buffer. Sort by urgency then cost desc.
        upcoming = sorted(
            [(name, item) for name, item in remaining.items()],
            key=lambda kv: (kv[1].deadline_stage, -kv[1].cost),
        )
        for name, item in upcoming:
            if balance - item.cost >= SAFETY_BUFFER:
                balance -= item.cost
                spent_this_stage += item.cost
                spent_so_far.append(BuyRecord(name, item.cost, idx))
                del remaining[name]

        total_spent = sum(r.cost for r in spent_so_far)
        print(f"{stage_name:<24}{income:>8}{cumulative_income:>11}"
              f"{spent_this_stage:>15}{total_spent:>22}")

    # Verdict
    print("-" * len(header.encode("utf-8")))
    cum_spent = sum(r.cost for r in spent_so_far)
    print(f"\nИТОГ:")
    print(f"  Доход суммарный:    {sum(INCOME_DELTA)}")
    print(f"  Потрачено:          {cum_spent}")
    print(f"  Финальный буфер:    {balance}")
    print(f"  Не куплено:         {sorted(remaining.keys()) or '(нет)'}")
    print()

    if remaining:
        print("✗ FAIL: остались must-buy с просроченным дедлайном.")
        return False
    if balance < 0:
        print(f"✗ FAIL: итоговый баланс отрицательный ({balance}).")
        return False
    if cum_spent > sum(INCOME_DELTA):
        print(f"✗ FAIL: суммарные расходы превысили доход.")
        return False

    print("✓ PASS: все must-buy закрыты к дедлайнам, итог ≥ 0, есть запас.")
    print()
    print("Хронология покупок:")
    for r in spent_so_far:
        print(f"  [{STAGE_NAMES[r.stage_bought]:<24}] {r.name:<35} {r.cost:>4} монет")
    return True


if __name__ == "__main__":
    success = simulate()
    raise SystemExit(0 if success else 1)
