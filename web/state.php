<?

# use one of these methods to access arsed's state file:
#$state_location = "http://turbo-gateway.example.com/trbo/arsed_state.json";
$state_location = "/var/tmp/arsed_state.json";

function fetch_state()
{
    global $state_location;
    
    if (substr($state_location, 0, 1) == '/') {
        $json = file_get_contents($state_location);
    } else {
        // create a new cURL resource
        $ch = curl_init();
        
        // set URL and other appropriate options
        curl_setopt($ch, CURLOPT_URL, $state_location);
        curl_setopt($ch, CURLOPT_HEADER, 0);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
        
        // grab URL and pass it to the browser
        $json = curl_exec($ch);
        
        // close cURL resource, and free up system resources
        curl_close($ch);
    }
    
    return json_decode($json, true);
}

function duration_str($s) {
    if ($s < 0) {
        $str = "-";
        $s *= -1;
    } else {
        $str = "";
    }
    
    $origs = $s;
    
    if ($s < 1) {
        $str .= "0s";
        return $str;
    }
    
    if ($s >= 24 * 60 * 60) {
        $d = floor($s / (24 * 60 * 60));
        $s -= $d * 24 * 60 * 60;
        $str .= $d . 'd ';
    }
    
    if ($s >= 60 * 60) {
        $d = floor($s / (60 * 60));
        $s -= $d * 60 * 60;
        $str .= $d . "h";
    }
    
    if ($s >= 60) {
        $d = floor($s / 60);
        $s -= $d * 60;
        $str .= $d . "m";
    }
    
    if ($s >= 1) {
        if ($origs < 60*60)
            $str .= floor($s) . "s";
    }
    
    return $str;
}


function logtime($tstamp)
{
    return gmstrftime('%Y-%m-%d %T', $tstamp);
}

function lastheard_sort($a, $b)
{
    if ($a['last_heard'] == $b['last_heard'])
        return 0;
        
    return ($a['last_heard'] > $b['last_heard']) ? -1 : 1;
}

if ($_GET['u']) {
    #error_log("state update");
    
    header('Content-Type: application/json; charset=utf-8');
    
    $j = array(); # returned json
    
    $state = fetch_state();
    $reg = $state['registry'];
    
    $j['at'] = "at " . logtime($state['time']) . " UTC - uptime "
        . duration_str($state['uptime']);
    $j['radios'] = "Radios: $state[ars_clients_here] registered on network, $state[ars_clients] total";
    
    $here = array();
    $away = array();
    foreach ($reg as $id => $radio) {
        if ($radio['state'] == 'here')
            array_push($here, $radio);
        else
            array_push($away, $radio);
    }
    
    uasort($here, 'lastheard_sort');
    uasort($away, 'lastheard_sort');
    
    $s = "<table>\n"
        . "<tr><th>Callsign</th> <th>ID</th> <th>Registered</th> <th>Last heard</th> <th>Last update</th></tr>\n";
    
    $shown = 0;
    foreach ($here as $radio) {
        $shown++;
        $s .= "<tr class='here'><td><a href='http://aprs.fi/?call=$radio[callsign]' target='_blank'>" . $radio['callsign'] . "</a></td><td>" . $radio['id'] . "</td><td>" . logtime($radio['first_heard']) . "</td><td>" . logtime($radio['last_heard']) . "</td>"
            . "<td>" . (isset($radio['heard_what']) ? $radio['heard_what'] : '') . "</td>"
            . "</tr>\n";
    }
    
    $s .= "<tr class='separator'><td> </td><td> </td><td> </td><td> </td><td> </td></tr>\n";

    foreach ($away as $radio) {
        if (!$radio['last_heard'])
            continue;
        $shown++;
        $s .= "<tr class='away'><td><a href='http://aprs.fi/?call=$radio[callsign]' target='_blank'>" . $radio['callsign'] . "</a></td><td>" . $radio['id'] . "</td><td>" . logtime($radio['first_heard']) . "</td>"
            . "<td>" . logtime($radio['last_heard']) . "</td>"
            . "<td>" . (isset($radio['away_reason']) ? $radio['away_reason'] : '') . "</td>"
            . "</tr>\n";
    }
    
    $s .= "</table>\n";
    
    $j['table'] = $s;
    
    $unshown = $state['ars_clients'] - $shown;
    $j['unshown'] = ($unshown) ? "Not showing $unshown configured radios which have never registered." : "";
    
    print json_encode($j);
    
    return;
} else {
    print_body();
}


function print_body()
{

print '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xml:lang="%language%" lang="%language%">
<head>
<title>ARS-E state</title>
<link rel="stylesheet" type="text/css" href="trbo.css" />
</head>

<body>
<script type="text/JavaScript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.5.1/jquery.min.js"></script>
<div class="title" id="title">ARS-E state <span id="at"></span></div>
<div class="radios" id="radios">Initializing ...</div>
<div class="table" id="table"></div>
<div class="unshown" id="unshown"></div>

<div class="footer">ARS-E daemon: Automatic Registration Service - Extendable</div>

<script type="text/JavaScript">

function repl(id, data, cb)
{
    t = 300;
    $(id).fadeOut(t, function() {
        $(this).html(data);
        cb();
        $(this).fadeIn(t);
    });
}

function refresh()
{
    $.ajax({
        url: "?u=1",
        cache: false,
        dataType: "json",
        success: function(data) {
            $("#at").html(data.at);
            repl("#radios", data.radios, function() {
                repl("#table", data.table, function(){
                    repl("#unshown", data.unshown, function(){});
                });
            });
            
            setTimeout(function() { refresh(); }, 6000);
        },
        error: function() {
            setTimeout(function() { refresh(); }, 30000);
        }
    });
}

refresh();

</script>
</body>
</html>
';

}


?>