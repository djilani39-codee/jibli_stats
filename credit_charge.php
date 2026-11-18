<?php
/**
 * credit_charge.php - driver credit top-up + debt ledger
 * Upload to: public_html/jibli/public/
 *
 * POST JSON + Header: X-App-Key
 * action = charge    : { user_id, amount }            -> add credit + record debt
 * action = add_debt  : { user_id, amount, note }      -> record manual debt (no credit)
 * action = pay       : { debt_id } or { user_id, all:1 } -> mark debt(s) paid
 * action = list      : {}                             -> list unpaid debts
 *
 * NOTE: This file is ASCII only on purpose (no Arabic text) to avoid
 * encoding corruption during upload.
 */
header('Content-Type: application/json; charset=utf-8');

$SECRET = 'JibliStats#2026$Charge';
$key = isset($_SERVER['HTTP_X_APP_KEY']) ? $_SERVER['HTTP_X_APP_KEY'] : (isset($_POST['key']) ? $_POST['key'] : '');
if (!hash_equals($SECRET, (string) $key)) {
    http_response_code(403);
    echo json_encode(array('success' => false, 'message' => 'forbidden'));
    exit;
}

$raw = file_get_contents('php://input');
$input = json_decode($raw, true);
if (!is_array($input)) {
    $input = $_POST;
}

$action = isset($input['action']) ? (string) $input['action'] : 'charge';
$userId = isset($input['user_id']) ? (int) $input['user_id'] : 0;
$amount = isset($input['amount']) ? (int) $input['amount'] : 0;
$note   = isset($input['note']) ? substr((string) $input['note'], 0, 191) : null;
$debtId = isset($input['debt_id']) ? (int) $input['debt_id'] : 0;
$payAll = !empty($input['all']);

require __DIR__ . '/../vendor/autoload.php';
$app = require_once __DIR__ . '/../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Database\Schema\Blueprint;

if (!Schema::hasTable('driver_debts')) {
    Schema::create('driver_debts', function (Blueprint $table) {
        $table->increments('id');
        $table->unsignedInteger('user_id');
        $table->integer('amount');
        $table->string('note', 191)->nullable();
        $table->tinyInteger('status')->default(0); // 0 = unpaid, 1 = paid
        $table->timestamp('created_at')->nullable();
        $table->timestamp('paid_at')->nullable();
        $table->index('user_id');
        $table->index('status');
    });
}

function isJibliDriver($userId)
{
    return DB::table('model_has_roles')
        ->where('model_id', $userId)
        ->where('model_type', 'App\\Models\\User')
        ->where('role_id', 5)
        ->exists();
}

try {

    // ============ LIST DEBTS ============
    if ($action === 'list') {
        $rows = DB::table('driver_debts as d')
            ->join('users as u', 'u.id', '=', 'd.user_id')
            ->where('d.status', 0)
            ->orderBy('d.id', 'desc')
            ->limit(500)
            ->get(array(
                'd.id',
                'd.user_id',
                'd.amount',
                'd.note',
                'd.created_at',
                'u.name as user_name',
                'u.phone as user_phone',
            ));

        $totals = array();
        foreach ($rows as $r) {
            $uid = (int) $r->user_id;
            if (!isset($totals[$uid])) {
                $totals[$uid] = array(
                    'user_id' => $uid,
                    'name'    => $r->user_name,
                    'phone'   => $r->user_phone,
                    'total'   => 0,
                    'count'   => 0,
                );
            }
            $totals[$uid]['total'] += (int) $r->amount;
            $totals[$uid]['count']++;
        }

        $entries = array();
        $grand = 0;
        foreach ($rows as $r) {
            $grand += (int) $r->amount;
            $entries[] = array(
                'id'      => (int) $r->id,
                'user_id' => (int) $r->user_id,
                'amount'  => (int) $r->amount,
                'note'    => $r->note,
                'date'    => $r->created_at ? date('Y-m-d H:i', strtotime($r->created_at)) : '',
            );
        }

        echo json_encode(array(
            'success'     => true,
            'entries'     => $entries,
            'totals'      => array_values($totals),
            'grand_total' => $grand,
        ));
        exit;
    }

    // ============ BASIC VALIDATION ============
    if ($userId <= 0) {
        http_response_code(400);
        echo json_encode(array('success' => false, 'message' => 'missing_user'));
        exit;
    }

    $user = DB::table('users')->where('id', $userId)->first();
    if (!$user) {
        http_response_code(404);
        echo json_encode(array('success' => false, 'message' => 'not_found'));
        exit;
    }
    if (!isJibliDriver($userId)) {
        http_response_code(400);
        echo json_encode(array('success' => false, 'message' => 'not_driver'));
        exit;
    }

    // ============ PAY DEBT(S) ============
    if ($action === 'pay') {
        if ($payAll) {
            $affected = DB::table('driver_debts')
                ->where('user_id', $userId)
                ->where('status', 0)
                ->update(array('status' => 1, 'paid_at' => now()));
            echo json_encode(array(
                'success'    => true,
                'paid_count' => $affected,
                'message'    => 'paid_all',
                'name'       => $user->name,
            ));
            exit;
        }

        if ($debtId <= 0) {
            http_response_code(400);
            echo json_encode(array('success' => false, 'message' => 'missing_debt_id'));
            exit;
        }
        $debt = DB::table('driver_debts')->where('id', $debtId)->where('user_id', $userId)->first();
        if (!$debt) {
            http_response_code(404);
            echo json_encode(array('success' => false, 'message' => 'debt_not_found'));
            exit;
        }
        DB::table('driver_debts')->where('id', $debtId)->update(array('status' => 1, 'paid_at' => now()));
        echo json_encode(array(
            'success' => true,
            'paid_id' => $debtId,
            'amount'  => (int) $debt->amount,
            'message' => 'paid_one',
        ));
        exit;
    }

    // ============ MANUAL DEBT ============
    if ($action === 'add_debt') {
        if ($amount <= 0 || $amount > 1000000) {
            http_response_code(400);
            echo json_encode(array('success' => false, 'message' => 'bad_amount'));
            exit;
        }
        $id = DB::table('driver_debts')->insertGetId(array(
            'user_id'    => $userId,
            'amount'     => $amount,
            'note'       => $note ? $note : 'manual',
            'status'     => 0,
            'created_at' => now(),
        ));
        $unpaid = (int) DB::table('driver_debts')
            ->where('user_id', $userId)
            ->where('status', 0)
            ->sum('amount');
        echo json_encode(array(
            'success'    => true,
            'debt_id'    => $id,
            'message'    => 'debt_added',
            'amount'     => $amount,
            'name'       => $user->name,
            'total_debt' => $unpaid,
        ));
        exit;
    }

    // ============ CHARGE CREDIT + RECORD DEBT ============
    if ($amount <= 0 || $amount > 1000000) {
        http_response_code(400);
        echo json_encode(array('success' => false, 'message' => 'bad_amount'));
        exit;
    }

    $old = (int) $user->credit;
    $new = $old + $amount;

    DB::beginTransaction();

    DB::table('users')->where('id', $userId)->update(array(
        'credit'     => $new,
        'updated_at' => now(),
    ));

    $debtId = DB::table('driver_debts')->insertGetId(array(
        'user_id'    => $userId,
        'amount'     => $amount,
        'note'       => 'charge',
        'status'     => 0,
        'created_at' => now(),
    ));

    $unpaid = (int) DB::table('driver_debts')
        ->where('user_id', $userId)
        ->where('status', 0)
        ->sum('amount');

    DB::commit();

    echo json_encode(array(
        'success'    => true,
        'user_id'    => $userId,
        'name'       => $user->name,
        'old'        => $old,
        'added'      => $amount,
        'new'        => $new,
        'debt_id'    => $debtId,
        'total_debt' => $unpaid,
        'message'    => 'charged',
    ));

} catch (\Throwable $e) {
    try {
        if (DB::transactionLevel() > 0) {
            DB::rollBack();
        }
    } catch (\Throwable $e2) {
    }
    http_response_code(500);
    echo json_encode(array('success' => false, 'message' => 'server_error', 'detail' => $e->getMessage()));
}
