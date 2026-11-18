<?php
/**
 * credit_charge.php — شحن فلكسي + دفتر ديون الموزعين
 * يُرفع في: public_html/jibli/public/
 *
 * POST JSON + Header: X-App-Key
 * action = charge    : { user_id, amount }            → شحن الرصيد + تسجيل دين
 * action = add_debt  : { user_id, amount, note }      → تسجيل دين يدوي (بدون شحن)
 * action = pay       : { debt_id } أو { user_id, all:1 } → تسديد دين / كل ديون موزع
 * action = list      : {}                             → قائمة الديون غير المسددة
 */
header('Content-Type: application/json; charset=utf-8');

$SECRET = 'JibliStats#2026$Charge';
$key = $_SERVER['HTTP_X_APP_KEY'] ?? ($_POST['key'] ?? '');
if (!hash_equals($SECRET, (string) $key)) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'forbidden'], JSON_UNESCAPED_UNICODE);
    exit;
}

$raw   = file_get_contents('php://input');
$input = json_decode($raw, true);
if (!is_array($input)) {
    $input = $_POST;
}

$action = isset($input['action']) ? (string) $input['action'] : 'charge';
$userId = isset($input['user_id']) ? (int) $input['user_id'] : 0;
$amount = isset($input['amount']) ? (int) $input['amount'] : 0;
$note   = isset($input['note']) ? mb_substr((string) $input['note'], 0, 191) : null;
$debtId = isset($input['debt_id']) ? (int) $input['debt_id'] : 0;
$payAll = !empty($input['all']);

require __DIR__ . '/../vendor/autoload.php';
$app = require_once __DIR__ . '/../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Database\Schema\Blueprint;

// ---------- إنشاء جدول الديون تلقائياً عند أول استخدام ----------
if (!Schema::hasTable('driver_debts')) {
    Schema::create('driver_debts', function (Blueprint $table) {
        $table->increments('id');
        $table->unsignedInteger('user_id');
        $table->integer('amount');
        $table->string('note', 191)->nullable();
        $table->tinyInteger('status')->default(0); // 0 = غير مسدد، 1 = مسدد
        $table->timestamp('created_at')->nullable();
        $table->timestamp('paid_at')->nullable();
        $table->index('user_id');
        $table->index('status');
    });
}

function isDriver($userId)
{
    return DB::table('model_has_roles')
        ->where('model_id', $userId)
        ->where('model_type', 'App\\Models\\User')
        ->where('role_id', 5)
        ->exists();
}

try {

    // ================= قائمة الديون =================
    if ($action === 'list') {
        $rows = DB::table('driver_debts as d')
            ->join('users as u', 'u.id', '=', 'd.user_id')
            ->where('d.status', 0)
            ->orderBy('d.id', 'desc')
            ->limit(500)
            ->get([
                'd.id',
                'd.user_id',
                'd.amount',
                'd.note',
                'd.created_at',
                'u.name as user_name',
                'u.phone as user_phone',
            ]);

        $totals = [];
        foreach ($rows as $r) {
            $uid = (int) $r->user_id;
            if (!isset($totals[$uid])) {
                $totals[$uid] = [
                    'user_id' => $uid,
                    'name'    => $r->user_name,
                    'phone'   => $r->user_phone,
                    'total'   => 0,
                    'count'   => 0,
                ];
            }
            $totals[$uid]['total'] += (int) $r->amount;
            $totals[$uid]['count']++;
        }

        echo json_encode([
            'success' => true,
            'entries' => $rows->map(function ($r) {
                return [
                    'id'       => (int) $r->id,
                    'user_id'  => (int) $r->user_id,
                    'amount'   => (int) $r->amount,
                    'note'     => $r->note,
                    'date'     => $r->created_at ? date('Y-m-d H:i', strtotime($r->created_at)) : '',
                ];
            })->values(),
            'totals' => array_values($totals),
            'grand_total' => (int) $rows->sum('amount'),
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }

    // ================= التحقق الأساسي للموزع =================
    if ($userId <= 0) {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'user_id مطلوب'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    $user = DB::table('users')->where('id', $userId)->first();
    if (!$user) {
        http_response_code(404);
        echo json_encode(['success' => false, 'message' => 'الموزع غير موجود'], JSON_UNESCAPED_UNICODE);
        exit;
    }
    if (!isDriver($userId)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'هذا المستخدم ليس موزعاً'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    // ================= تسديد دين (واحد أو الكل) =================
    if ($action === 'pay') {
        if ($payAll) {
            $affected = DB::table('driver_debts')
                ->where('user_id', $userId)
                ->where('status', 0)
                ->update(['status' => 1, 'paid_at' => now()]);
            echo json_encode([
                'success' => true,
                'paid_count' => $affected,
                'message' => 'تم تسديد كل ديون ' . $user->name,
            ], JSON_UNESCAPED_UNICODE);
            exit;
        }

        if ($debtId <= 0) {
            http_response_code(400);
            echo json_encode(['success' => false, 'message' => 'debt_id مطلوب'], JSON_UNESCAPED_UNICODE);
            exit;
        }
        $debt = DB::table('driver_debts')->where('id', $debtId)->where('user_id', $userId)->first();
        if (!$debt) {
            http_response_code(404);
            echo json_encode(['success' => false, 'message' => 'الدين غير موجود'], JSON_UNESCAPED_UNICODE);
            exit;
        }
        DB::table('driver_debts')->where('id', $debtId)->update(['status' => 1, 'paid_at' => now()]);
        echo json_encode([
            'success' => true,
            'paid_id' => $debtId,
            'message' => 'تم تسديد ' . $debt->amount . ' دج',
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }

    // ================= دين يدوي =================
    if ($action === 'add_debt') {
        if ($amount <= 0 || $amount > 1000000) {
            http_response_code(400);
            echo json_encode(['success' => false, 'message' => 'المبلغ غير صالح'], JSON_UNESCAPED_UNICODE);
            exit;
        }
        $id = DB::table('driver_debts')->insertGetId([
            'user_id'    => $userId,
            'amount'     => $amount,
            'note'       => $note ?: 'دين يدوي',
            'status'     => 0,
            'created_at' => now(),
        ]);
        echo json_encode([
            'success' => true,
            'debt_id' => $id,
            'message' => 'تم تسجيل دين ' . $amount . ' دج على ' . $user->name,
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }

    // ================= شحن الرصيد + تسجيل الدين =================
    if ($amount <= 0 || $amount > 1000000) {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'المبلغ غير صالح (يجب أن يكون أكبر من 0)'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    $old = (int) $user->credit;
    $new = $old + $amount;

    DB::beginTransaction();

    DB::table('users')->where('id', $userId)->update([
        'credit'     => $new,
        'updated_at' => now(),
    ]);

    $debtId = DB::table('driver_debts')->insertGetId([
        'user_id'    => $userId,
        'amount'     => $amount,
        'note'       => 'شحن فلكسي',
        'status'     => 0,
        'created_at' => now(),
    ]);

    $unpaid = (int) DB::table('driver_debts')
        ->where('user_id', $userId)
        ->where('status', 0)
        ->sum('amount');

    DB::commit();

    echo json_encode([
        'success'    => true,
        'user_id'    => $userId,
        'name'       => $user->name,
        'old'        => $old,
        'added'      => $amount,
        'new'        => $new,
        'debt_id'    => $debtId,
        'total_debt' => $unpaid,
    ], JSON_UNESCAPED_UNICODE);

} catch (\Throwable $e) {
    if (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => $e->getMessage()], JSON_UNESCAPED_UNICODE);
}
