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
            $status = 5; // حالة التوصيل
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

            // 2. حساب إحصائيات الفترة المختارة
            $stats = $this->calculateStats($from, $to, $status);

            // 3. تحليل الأشهر (الرسم البياني)
            $monthlyTrend = [];
            for ($i = 5; $i >= 0; $i--) {
                $mStart = Carbon::now($tz)->subMonths($i)->startOfMonth();
                $mEnd = Carbon::now($tz)->subMonths($i)->endOfMonth();
                $mStats = $this->calculateStats($mStart, $mEnd, $status);
                
                $monthlyTrend[] = [
                    'month_name' => $mStart->translatedFormat('M'),
                    'profit' => round($mStats['profit'], 2),
                    'orders' => $mStats['count']
                ];
            }

            // 4. السجل اليومي + أداء الموصلين (آخر 30 يوم)
            $dailyBreakdown = DB::table('orders')
                ->where('order_status_id', $status)
                ->select(DB::raw('DATE(created_at) as order_day'))
                ->groupBy('order_day')
                ->orderBy('order_day', 'desc')
                ->limit(30) // تم التغيير من 7 إلى 30 يوم
                ->get()
                ->map(function($day) use ($status, $tz) {
                    $dStart = Carbon::parse($day->order_day, $tz)->startOfDay();
                    $dEnd = Carbon::parse($day->order_day, $tz)->endOfDay();
                    
                    // حساب أرباح اليوم
                    $dStats = $this->calculateStats($dStart, $dEnd, $status);
                    
                    // جلب الموصلين لهذا اليوم
                    $drivers = DB::table('orders as o')
                        ->join('users as u', 'u.id', '=', 'o.driver_id')
                        ->where('o.order_status_id', $status)
                        ->whereBetween('o.created_at', [$dStart, $dEnd])
                        ->select('u.name', DB::raw('count(o.id) as orders_count'))
                        ->groupBy('u.id', 'u.name')
                        ->get();

                    return [
                        'order_day' => $day->order_day,
                        'profit_total' => round($dStats['profit'], 2),
                        'orders_count' => $dStats['count'],
                        'avg_profit_per_order' => $dStats['count'] > 0 ? round($dStats['profit'] / $dStats['count'], 1) : 0,
                        'drivers' => $drivers
                    ];
                });

            // 5. الموزعون النشطون اليوم
            $activeDrivers = DB::table('orders as o')
                ->join('users as u', 'u.id', '=', 'o.driver_id')
                ->where('o.order_status_id', $status)
                ->whereBetween('o.created_at', [Carbon::today($tz)->startOfDay(), Carbon::today($tz)->endOfDay()])
                ->select('u.name', DB::raw('count(o.id) as orders_delivered'))
                ->groupBy('u.id', 'u.name')
                ->get();

            // 6. ما يجب أن يدفعه كل محل (العمولات)
            $marketPayments = DB::table('product_orders as po')
                ->join('orders as o', 'o.id', '=', 'po.order_id')
                ->join('products as p', 'p.id', '=', 'po.product_id')
                ->join('markets as m', 'm.id', '=', 'p.market_id')
                ->where('o.order_status_id', $status)
                ->whereBetween('o.created_at', [$from, $to])
                ->select('m.name as market_name', DB::raw('SUM(po.price * m.admin_commission / 100) as commission_owed'))
                ->groupBy('m.id', 'm.name')
                ->orderBy('commission_owed', 'desc')
                ->get();

            return response()->json([
                'success' => true,
                'data' => [
                    'period_profit' => round($stats['profit'], 2),
                    'period_avg' => $stats['count'] > 0 ? round($stats['profit'] / $stats['count'], 2) : 0,
                    'monthly_trend' => $monthlyTrend,
                    'daily_breakdown' => $dailyBreakdown,
                    'active_drivers' => $activeDrivers,
                    'market_payments' => $marketPayments
                ]
            ]);

        } catch (\Exception $e) {
            return response()->json(['success' => false, 'error' => $e->getMessage()], 500);
        }
    }

    private function calculateStats($from, $to, $status) {
        $orders = DB::table('orders')->where('order_status_id', $status)->whereBetween('created_at', [$from, $to]);
        $count = $orders->count();
        $serviceFees = $orders->sum(DB::raw('service_fee + 30'));
        $commissions = DB::table('product_orders as po')
            ->join('orders as o', 'o.id', '=', 'po.order_id')
            ->join('products as p', 'p.id', '=', 'po.product_id')
            ->join('markets as m', 'm.id', '=', 'p.market_id')
            ->where('o.order_status_id', $status)
            ->whereBetween('o.created_at', [$from, $to])
            ->sum(DB::raw('po.price * m.admin_commission / 100'));
        return ['profit' => (float)$commissions + $serviceFees, 'count' => $count];
    }
}