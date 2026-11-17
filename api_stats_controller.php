<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Carbon;

class StatsController extends Controller
{
    public function getDashboardStats(Request $request)
    {
        try {
            $period = $request->get('period', 'today');
            $status = 5; // حالة الطلب "مكتمل"
            $tz = 'Africa/Algiers';

            // 1. تحديد النطاق الزمني
            if ($period == 'yesterday') {
                $from = Carbon::yesterday($tz)->startOfDay();
                $to = Carbon::yesterday($tz)->endOfDay();
            } elseif ($period == 'week') {
                $from = Carbon::now($tz)->startOfWeek(Carbon::SATURDAY);
                $to = Carbon::now($tz)->endOfWeek(Carbon::FRIDAY);
            } elseif ($period == 'month') {
                $from = Carbon::now($tz)->startOfMonth();
                $to = Carbon::now($tz)->endOfMonth();
            } else {
                $from = Carbon::today($tz)->startOfDay();
                $to = Carbon::today($tz)->endOfDay();
            }

            // 2. إحصائيات الفترة الحالية
            $stats = $this->calculateStats($from, $to, $status);

            // 3. تحليل الأشهر الستة الأخيرة + المتوسط الشهري
            $monthlyTrend = [];
            for ($i = 5; $i >= 0; $i--) {
                $mStart = Carbon::now($tz)->subMonths($i)->startOfMonth();
                $mEnd = Carbon::now($tz)->subMonths($i)->endOfMonth();
                $mStats = $this->calculateStats($mStart, $mEnd, $status);
                
                // حساب المتوسط لهذا الشهر
                $monthlyAvg = $mStats['count'] > 0 ? ($mStats['profit'] / $mStats['count']) : 0;

                $monthlyTrend[] = [
                    'month_name' => $mStart->translatedFormat('M'),
                    'profit' => round($mStats['profit'], 2),
                    'orders' => $mStats['count'],
                    'monthly_avg' => round($monthlyAvg, 2) // العمود الثالث المطلوب بالدينار
                ];
            }

            // 4. السجل اليومي (آخر 30 يوم) مع معالجة الطلبات بدون موزع
            $dailyBreakdown = DB::table('orders')
                ->where('order_status_id', $status)
                ->select(DB::raw('DATE(created_at) as order_day'))
                ->groupBy('order_day')
                ->orderBy('order_day', 'desc')
                ->limit(30)
                ->get()
                ->map(function($day) use ($status, $tz) {
                    $dStart = Carbon::parse($day->order_day, $tz)->startOfDay();
                    $dEnd = Carbon::parse($day->order_day, $tz)->endOfDay();
                    $dStats = $this->calculateStats($dStart, $dEnd, $status);
                    
                    // جلب الموزعين + احتساب الطلبات بدون موزع (Left Join)
                    $drivers = DB::table('orders as o')
                        ->leftJoin('users as u', 'u.id', '=', 'o.driver_id')
                        ->where('o.order_status_id', $status)
                        ->whereBetween('o.created_at', [$dStart, $dEnd])
                        ->select(
                            DB::raw('IFNULL(u.name, "استلام من المحل / بدون موزع") as name'), 
                            DB::raw('count(o.id) as orders_count')
                        )
                        ->groupBy('o.driver_id', 'u.name')
                        ->get();

                    return [
                        'order_day' => $day->order_day,
                        'profit_total' => round($dStats['profit'], 2),
                        'orders_count' => $dStats['count'],
                        'avg_profit_per_order' => $dStats['count'] > 0 ? round($dStats['profit'] / $dStats['count'], 1) : 0,
                        'drivers' => $drivers
                    ];
                });

            // 5. طلبات اليوم (رقم الطلب، الزبون، السائق، وقت الحجز)
            $todayOrders = DB::table('orders as o')
                ->leftJoin('users as u', 'u.id', '=', 'o.user_id')
                ->leftJoin('users as d', 'd.id', '=', 'o.driver_id')
                ->whereBetween('o.created_at', [Carbon::today($tz)->startOfDay(), Carbon::today($tz)->endOfDay()])
                ->orderBy('o.id', 'desc')
                ->select(
                    'o.id as order_id',
                    'u.name as customer_name',
                    'd.name as driver_name',
                    'o.created_at'
                )
                ->limit(300)
                ->get()
                ->map(function ($o) use ($tz) {
                    return [
                        'order_id' => $o->order_id,
                        'customer_name' => $o->customer_name,
                        'driver_name' => $o->driver_name,
                        'booked_at' => Carbon::parse($o->created_at)->setTimezone($tz)->format('H:i'),
                    ];
                });

            return response()->json([
                'success' => true,
                'data' => [
                    'period_profit' => round($stats['profit'], 2),
                    'period_avg' => $stats['count'] > 0 ? round($stats['profit'] / $stats['count'], 2) : 0,
                    'monthly_trend' => $monthlyTrend,
                    'daily_breakdown' => $dailyBreakdown,
                    'today_orders' => $todayOrders
                ]
            ]);

        } catch (\Exception $e) {
            return response()->json(['success' => false, 'error' => $e->getMessage()], 500);
        }
    }

    private function calculateStats($from, $to, $status) {
        $ordersQuery = DB::table('orders')
            ->where('order_status_id', $status)
            ->whereBetween('created_at', [$from, $to]);

        $count = $ordersQuery->count();
        $serviceFeesAndFixed = $ordersQuery->sum(DB::raw('service_fee + 30'));

        $commissions = DB::table('product_orders as po')
            ->join('orders as o', 'o.id', '=', 'po.order_id')
            ->join('products as p', 'p.id', '=', 'po.product_id')
            ->join('markets as m', 'm.id', '=', 'p.market_id')
            ->where('o.order_status_id', $status)
            ->whereBetween('o.created_at', [$from, $to])
            ->select(DB::raw('SUM(po.price * po.quantity * m.admin_commission / 100) as total_admin_percent'))
            ->first()->total_admin_percent ?? 0;

        return [
            'profit' => (float)$commissions + (float)$serviceFeesAndFixed, 
            'count' => $count
        ];
    }
    
    public function getMarketsDebts(Request $request)
{
    try {
        $status = 5; // حالة "تم التسليم" فقط كما في الإكسيل
        $tz = 'Africa/Algiers';

        $markets = \App\Models\Market::select('id', 'name', 'admin_commission')
            ->get()
            ->map(function ($market) use ($status) {
                
                // 1. حساب العمولات المستحقة فقط للطلبات المكتملة وغير المسواة
                // (نفس منطق لوحة التحكم: Export Admin Commissions — admin_commission_paid = 0)
                $marketData = \DB::table('product_orders as po')
                    ->join('orders as o', 'o.id', '=', 'po.order_id')
                    ->join('products as p', 'p.id', '=', 'po.product_id')
                    ->where('p.market_id', $market->id)
                    ->where('o.order_status_id', $status) // التصفية حسب الحالة 5
                    ->where('o.admin_commission_paid', 0) // فقط الطلبات غير المسواة
                    ->select(
                        \DB::raw('COALESCE(SUM(po.price * po.quantity), 0) as total_orders_amount'),
                        \DB::raw('COALESCE(SUM(po.price * po.quantity), 0) * ' . (float)($market->admin_commission ?? 0) . ' / 100 as commission'),
                        \DB::raw('COUNT(DISTINCT o.id) as orders_count')
                    )
                    ->first();

                $totalOrdersAmount = (float)($marketData->total_orders_amount ?? 0);
                $currentDebt = (float)($marketData->commission ?? 0);

                // تفاصيل الطلبات غير المسواة (صف لكل منتج مطلوب — مثل Export Admin Commissions)
                $details = \DB::table('product_orders as po')
                    ->join('orders as o', 'o.id', '=', 'po.order_id')
                    ->join('products as p', 'p.id', '=', 'po.product_id')
                    ->leftJoin('product_order_options as poo', 'poo.product_order_id', '=', 'po.id')
                    ->leftJoin('options as op', 'op.id', '=', 'poo.option_id')
                    ->where('p.market_id', $market->id)
                    ->where('o.order_status_id', $status)
                    ->where('o.admin_commission_paid', 0)
                    ->select(
                        'po.id as po_id',
                        'p.name as product_name',
                        'po.price',
                        'po.quantity',
                        'o.id as order_id',
                        'o.created_at',
                        'op.name as option_name'
                    )
                    ->orderBy('o.id', 'desc')
                    ->limit(500)
                    ->get();

                // تجميع الخيارات مع كل منتج
                $rows = [];
                foreach ($details as $d) {
                    $key = $d->po_id;
                    if (!isset($rows[$key])) {
                        $total = (float)$d->price * (int)$d->quantity;
                        $rows[$key] = [
                            'product_name' => $d->product_name,
                            'price' => round((float)$d->price, 2),
                            'quantity' => (int)$d->quantity,
                            'total' => round($total, 2),
                            'commission' => round($total * (float)($market->admin_commission ?? 0) / 100, 2),
                            'order_id' => $d->order_id,
                            'ordered_at' => Carbon::parse($d->created_at)->setTimezone($tz)->format('Y-m-d H:i'),
                            'options' => [],
                        ];
                    }
                    if (!empty($d->option_name)) {
                        $rows[$key]['options'][] = $d->option_name;
                    }
                }
                $rows = array_values($rows);

                return [
                    'id' => $market->id,
                    'name' => $market->name,
                    'admin_commission' => (float)($market->admin_commission ?? 0),
                    'orders_count' => (int)($marketData->orders_count ?? 0),
                    'total_orders_amount' => round($totalOrdersAmount, 2),
                    'debt' => round($currentDebt, 2),
                    'details' => $rows,
                ];
            })
            ->where('debt', '>', 0)
            ->values();

        return response()->json([
            'success' => true,
            'data' => $markets,
            'total_debts' => $markets->sum('debt'),
            'total_orders_amount' => $markets->sum('total_orders_amount'),
        ]);

    } catch (\Exception $e) {
        return response()->json(['success' => false, 'message' => $e->getMessage()], 500);
    }
}
}
